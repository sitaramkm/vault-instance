#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# vault.sh — Vault lifecycle helper
#
# Commands:
#   ./helper/vault.sh create
#   ./helper/vault.sh destroy
#   ./helper/vault.sh allow <CIDR>
#   ./helper/vault.sh seed-sample-secrets
#
# Conventions:
#   - common.env        → shared config (committed)
#   - secrets-hub.env   → future use (gitignored)
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform"

ACTION="${1:-}"
shift || true

# ------------------------------------------------------------
# Load environment
# ------------------------------------------------------------

if [[ ! -f "${ROOT_DIR}/common.env" ]]; then
  echo "ERROR: common.env not found in repo root"
  exit 1
fi
source "${ROOT_DIR}/common.env"

  # ------------------------------------------------------------
# Validate required variables
# ------------------------------------------------------------

: "${RESOURCE_PREFIX:?RESOURCE_PREFIX must be set in common.env}"
: "${TF_VAR_zone_id:?TF_VAR_zone_id must be set in common.env}"
: "${TF_VAR_domain_name:?TF_VAR_domain_name must be set in common.env}"
: "${TF_VAR_owner:?TF_VAR_owner must be set in common.env}"

# Terraform variable injection
export TF_VAR_resource_prefix="${RESOURCE_PREFIX}"

# ------------------------------------------------------------
# AWS context handling
# ------------------------------------------------------------

if [[ -n "${AWS_PROFILE:-}" ]]; then
  export AWS_PROFILE
fi

if [[ -n "${AWS_REGION:-}" ]]; then
  export AWS_REGION
  export AWS_DEFAULT_REGION="${AWS_REGION}"
fi

# Verify AWS login
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  echo "ERROR: AWS CLI is not authenticated."
  echo "Run 'aws sso login' or 'aws configure' and try again."
  exit 1
fi

awscli() {
  : "${AWS_REGION:?AWS_REGION must be set}"
  : "${AWS_PROFILE:?AWS_PROFILE must be set}"

  aws --region "$AWS_REGION" --profile "$AWS_PROFILE" "$@"
}

REGION="${AWS_REGION:-$(aws configure get region)}"

if [[ -z "${REGION}" ]]; then
  echo "ERROR: AWS region not set. Define AWS_REGION in common.env"
  exit 1
fi

echo "AWS Profile : ${AWS_PROFILE}"
echo "AWS Region  : ${AWS_REGION}"
echo "Resource ID : ${RESOURCE_PREFIX}"
echo

# ------------------------------------------------------------
# Terraform variable injection
# ------------------------------------------------------------

if [[ -n "${AWS_REGION:-}" ]]; then
  export TF_VAR_region="${AWS_REGION}"
fi

if [[ -n "${AWS_PROFILE:-}" ]]; then
  export TF_VAR_aws_profile="${AWS_PROFILE}"
fi

# ------------------------------------------------------------
# Terraform helpers
# ------------------------------------------------------------

terraform_init() {
  cd "${TERRAFORM_DIR}"
  terraform init
}

terraform_apply() {
  terraform_init
  terraform apply -auto-approve
}

terraform_destroy() {
  terraform_init
  terraform destroy -auto-approve
}

# ------------------------------------------------------------
# SSM cleanup (used on destroy)
# ------------------------------------------------------------

cleanup_ssm_parameters() {
  local prefix="/${RESOURCE_PREFIX}-ssm"

  echo "Cleaning up SSM parameters under ${prefix}"

  PARAMS=$(awscli ssm describe-parameters \
    --query "Parameters[?starts_with(Name, '${prefix}')].Name" \
    --output text)

  if [[ -z "${PARAMS}" ]]; then
    echo "No SSM parameters found for ${prefix}"
    return
  fi

  for p in ${PARAMS}; do
    echo "Deleting SSM parameter: ${p}"
    awscli ssm delete-parameter --name "${p}"
  done
}

cleanup_more_resources_if_any() {
   echo "Cleaning up additional resources created by Terraform"
   rm -rf ${TERRAFORM_DIR}/terraform_outputs.json || true
   rm -rf ${TERRAFORM_DIR}/.terraform || true
   rm -rf ${TERRAFORM_DIR}/.terraform.lock.hcl || true
   rm -rf ${TERRAFORM_DIR}/terraform.tfstate* || true
   rm -rf ${ROOT_DIR}/secrets-hub-config.txt || true
   rm -rf ${ROOT_DIR}/vault_info.env || true
}

# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------

create() {
  echo "=== Creating Vault infrastructure ==="
  terraform_apply || {
    echo "Terraform apply failed; aborting."
    exit 1
  }
  echo "=== Retrieving Vault info ==="
  cd "${TERRAFORM_DIR}"
  terraform output -json > ${TERRAFORM_DIR}/terraform_outputs.json
  VAULT_URL=$(jq -r ".vault_url.value" terraform_outputs.json)
  echo "Vault URL: $VAULT_URL"
  echo "export VAULT_ADDR=\"$VAULT_URL\"" > "${ROOT_DIR}/vault_info.env"
}

destroy() {
  echo "=== Destroying Vault infrastructure ==="
  terraform_destroy
  cleanup_ssm_parameters
  cleanup_more_resources_if_any
}

allow() {
  local cidr="${1:-}"
  if [[ -z "$cidr" ]]; then
    echo "Usage: $0 allow <CIDR>"
    exit 1
  fi

  echo "=== Allowing access from CIDR: ${cidr} ==="

  CIDRS_JSON=$(python3 - "$cidr" <<'PY'
import json, sys
print(json.dumps(sys.argv[1:]))
PY
)
  cd "${TERRAFORM_DIR}"
  echo "Applying allowed_additional_cidrs=${CIDRS_JSON}"
  terraform apply -var "allowed_additional_cidrs=${CIDRS_JSON}" -auto-approve
}

create_sample_secrets() {
  echo "=== Seeding sample Vault secrets ==="
  "${ROOT_DIR}/scripts/seed_vault.sh" "$@"
}

get_token() {
  local token
  local PREFIX="/${RESOURCE_PREFIX}-ssm"
  local VAULT_INFO_FILE="${ROOT_DIR}/vault_info.env"

  token="$(awscli ssm get-parameter \
    --name "${PREFIX}/root_token" \
    --with-decryption \
    --query Parameter.Value \
    --output text)"

  if [[ -z "$token" ]]; then
    echo "ERROR: Token retrieval returned empty value"
    exit 1
  fi

  echo "Retrieved Vault token:"
  echo "$token"

  # Ensure file exists
  touch "${VAULT_INFO_FILE}"

  # Remove existing VAULT_TOKEN line if present
  sed -i.bak '/^export VAULT_TOKEN=/d' "${VAULT_INFO_FILE}"

  # Append fresh token
  echo "export VAULT_TOKEN=\"$token\"" >> "${VAULT_INFO_FILE}"

  rm -f "${VAULT_INFO_FILE}.bak"
}


# ------------------------------------------------------------
# Command dispatch
# ------------------------------------------------------------

case "${ACTION}" in
  create) create ;;
  destroy) destroy ;;
  allow) allow "$@" ;;
  create-sample-secrets) create_sample_secrets "$@" ;;
  get-token) get_token "$@" ;;
  *)
    echo "Usage:"
    echo "  ./helper/vault.sh create"
    echo "  ./helper/vault.sh destroy"
    echo "  ./helper/vault.sh allow <CIDR>"
    echo "  ./helper/vault.sh create-sample-secrets"
    echo "  ./helper/vault.sh get-token"
    exit 1
    ;;
esac
