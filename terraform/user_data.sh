#!/bin/bash
set -euo pipefail


# Terraform-provided values (lowercase)
vault_version="${vault_version}"
vault_domain="${vault_domain}"
kms_key_id="${kms_key_id}"
region="${region}"
ssm_prefix="${ssm_prefix}"

export DEBIAN_FRONTEND=noninteractive
export AWS_REGION="$region"
export AWS_DEFAULT_REGION="$region"


apt-get update -y
apt-get install -y unzip curl jq awscli gnupg lsb-release

# Install Vault
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor > /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list
apt-get update -y
apt-get install -y "vault=$vault_version" || apt-get install -y vault

mkdir -p /etc/vault.d /opt/vault/data
chown -R vault:vault /opt/vault
chmod 750 /opt/vault

cat >/etc/vault.d/vault.hcl <<EOF
ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "file" {
  path = "/opt/vault/data"
}

seal "awskms" {
  kms_key_id = "$kms_key_id"
  region     = "$region"
}

api_addr = "https://$vault_domain"
disable_mlock = true
EOF

chown vault:vault /etc/vault.d/vault.hcl
chmod 640 /etc/vault.d/vault.hcl

systemctl enable vault
systemctl restart vault

# Vault talks to itself locally
export VAULT_ADDR="http://127.0.0.1:8200"

# Wait for Vault
for i in $(seq 1 60); do
  if curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if [ ! -f /opt/vault/init.done ]; then
  vault operator init -format=json > /opt/vault/init.json
  root_token=$(jq -r '.root_token' /opt/vault/init.json)

  aws ssm put-parameter \
    --region "$region" \
    --name "$ssm_prefix/root_token" \
    --type SecureString \
    --value "$root_token" \
    --overwrite


  export VAULT_TOKEN="$root_token"

  # Ensure KV v2
  vault secrets enable -path=sample-secrets kv-v2 || true

  # Demo policy
  cat >/opt/vault/demo-policy.hcl <<'POL'
path "sample-secrets/data/demo/*" {
  capabilities = ["read", "list"]
}
path "sample-secrets/metadata/demo/*" {
  capabilities = ["read", "list"]
}
POL

  vault policy write demo /opt/vault/demo-policy.hcl

  vault token create -policy=demo -ttl=24h -format=json > /opt/vault/demo_token.json
  demo_token=$(jq -r '.auth.client_token' /opt/vault/demo_token.json)

  aws ssm put-parameter \
    --region "$region" \
    --name "$ssm_prefix/demo_token" \
    --type SecureString \
    --value "$demo_token" \
    --overwrite


  # Seed sample secrets
  vault kv put sample-secrets/demo/hello message="hello from vault demo"
  vault kv put sample-secrets/demo/app username="demo-user" password="demo-pass"

  touch /opt/vault/init.done
fi
