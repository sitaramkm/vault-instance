#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Load env file if present ---
SH_ENV_FILE="${ROOT_DIR}/secrets-hub.env"
if [[ -f "$SH_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$SH_ENV_FILE"
else
  echo -e "ENV file NOT found at '${SH_ENV_FILE}'."
fi

VAULT_ENV_FILE="${ROOT_DIR}/vault_info.env"
if [[ -f "$VAULT_ENV_FILE" ]]; then
  source "$VAULT_ENV_FILE"


: "${VAULT_ADDR:?VAULT_ADDR not found. Must be set.}"
: "${VAULT_TOKEN:?VAULT_TOKEN not found. Must be set.}"

# Optional TLS for CLI
export VAULT_CACERT="${VAULT_CACERT:-}"
export VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-}"

export MOUNT_PATH="${RESOURCE_PREFIX}-vault"   # KV v2 mount
export ROLE_NAME="${MOUNT_PATH}-Role"
export POLICY_NAME="${ROLE_NAME}-Policy"
export JWT_PATH="${MOUNT_PATH}-jwt-authenticator"
export TOKEN_TTL="3600"  # seconds
export SECRET_PATH="secret/data/${MOUNT_PATH}/${SECRETS_NAME}"

echo ""
echo -e "Vault address    : ${VAULT_ADDR}"
echo -e "Mount path       : ${MOUNT_PATH}"
echo -e "Role name        : ${ROLE_NAME}"
echo -e "Auth (JWT) path  : ${JWT_PATH}"
echo -e "Discovery base   : ${OIDC_DISCOVERY_URL}"
echo ""

# --- Resolve issuer exactly ---
OIDC_DISCOVERY_CA_PEM="${OIDC_DISCOVERY_CA_PEM:-}" # optional CA PEM file
OIDC_ISSUER="${OIDC_ISSUER:-}" # don't compute issuer if OIDC_ISSUER is set
base_disc="${OIDC_DISCOVERY_URL%%/.well-known/*}"     # strip accidental suffix
disc_url="${base_disc%/}/.well-known/openid-configuration"
issuer="${OIDC_ISSUER}"
if [[ -z "$issuer" ]]; then
  issuer="$(curl -sS "${disc_url}" | jq -r '.issuer')"
  if [[ -z "$issuer" || "$issuer" == "null" ]]; then
    echo -e "Failed to resolve issuer from ${disc_url}"; exit 1
  fi
fi

# --- Check if we can reach Vault ---
if ! vault status -address="${VAULT_ADDR}" >/dev/null 2>&1; then
  echo -e "Warning: 'vault status' failed; verify VAULT_ADDR/VAULT_CACERT/VAULT_SKIP_VERIFY and token."
fi

if ! vault secrets list -address="${VAULT_ADDR}" | grep -q "^${MOUNT_PATH}/"; then
  vault secrets enable -address="${VAULT_ADDR}" -path="${MOUNT_PATH}" kv-v2 >/dev/null
  echo "✅ Enabled KV v2 mount: ${MOUNT_PATH}"
else
  echo "ℹ️  KV mount '${MOUNT_PATH}' already exists"
fi

# --- Policy (create or override) ---
if vault policy read -address="${VAULT_ADDR}" "${POLICY_NAME}" >/dev/null 2>&1; then
  echo -e "Policy '${POLICY_NAME}' exists; it will be overwritten."
fi
vault policy write -address="${VAULT_ADDR}" "${POLICY_NAME}" - <<EOF
path "${MOUNT_PATH}/data/*" {
  capabilities = ["read", "list", "create", "update", "delete"]
}

path "${MOUNT_PATH}/metadata/*" {
  capabilities = ["read", "list"]
}

path "sys/mounts/${MOUNT_PATH}" {
  capabilities = ["read"]
}
EOF

echo -e "✅ Policy ready: ${POLICY_NAME}"

# --- Enable JWT auth backend ---
if ! vault auth list -address="${VAULT_ADDR}" | grep -q "^${JWT_PATH}/"; then
  vault auth enable -address="${VAULT_ADDR}" -path="${JWT_PATH}" jwt >/dev/null
  echo -e "✅ Enabled auth/${JWT_PATH}"
else
  echo -e "ℹ️  auth/${JWT_PATH} already enabled"
fi

# --- Configure JWT backend ---
cfg_args=( oidc_discovery_url="${base_disc}" bound_issuer="${issuer}" )
if [[ -n "${OIDC_DISCOVERY_CA_PEM}" ]]; then
  [[ -r "${OIDC_DISCOVERY_CA_PEM}" ]] || { echo -e "Not readable: ${OIDC_DISCOVERY_CA_PEM}"; exit 1; }
  cfg_args+=( oidc_discovery_ca_pem=@"${OIDC_DISCOVERY_CA_PEM}" )
fi
vault write -address="${VAULT_ADDR}" "auth/${JWT_PATH}/config" "${cfg_args[@]}" >/dev/null
echo -e "✅ Configured auth/${JWT_PATH} (discovery='${base_disc}', issuer='${issuer}')"

# --- Create/override role ---
role_body=$(cat <<JSON
{
  "role_type": "jwt",
  "user_claim": "sub",
  "bound_audiences": ["${OIDC_AUDIENCE}"],
  "token_policies": ["${POLICY_NAME}"],
  "token_ttl": ${TOKEN_TTL},
  "bound_claims": { "sub": ["${SUBJECT}"] }
}
JSON
)
echo "${role_body}" | vault write -address="${VAULT_ADDR}" "auth/${JWT_PATH}/role/${ROLE_NAME}" - >/dev/null
echo -e "✅ Role ready: ${ROLE_NAME}"

# --- Create sample secrets  ---

echo -e "Seeding ${NUM_OF_SAMPLE_SECRETS} secrets into '${SECRET_PATH}'..."
for i in $(seq 1 "${NUM_OF_SAMPLE_SECRETS}"); do
  k=$(openssl rand -hex 8)
  v=$(openssl rand -hex 16)
  vault kv put -address="${VAULT_ADDR}" -mount="${MOUNT_PATH}" "${SECRETS_NAME}/${i}" "key=${k}" "value=${v}" >/dev/null || true
done
echo -e "✅ Seeded ${NUM_OF_SAMPLE_SECRETS} secrets."

# --- Summary ---
echo ""
echo -e "Use the following info in CyberArk Secrets Hub to register Vault."
echo -e "Vault address      : ${VAULT_ADDR}"
echo -e "Mount path         : ${MOUNT_PATH}"
echo -e "Role name          : ${ROLE_NAME}"
echo -e "Authentication path: ${JWT_PATH}"
echo -e "Issuer (exact)     : ${issuer}"  