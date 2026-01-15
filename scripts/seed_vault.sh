#!/bin/bash
set -euo pipefail

# Usage:
#   ./seed_vault.sh <aws_profile> <aws_region> <ssm_prefix> <vault_fqdn>
#
# Example:
#   ./seed_vault.sh my-corp-profile us-east-1 /vault-instance vault.example.com

AWS_PROFILE="$1"
AWS_REGION="$2"
SSM_PREFIX="$3"
VAULT_FQDN="$4"

export AWS_PROFILE AWS_REGION
export VAULT_ADDR="https://${VAULT_FQDN}"

ROOT_TOKEN="$(aws --profile $AWS_PROFILE ssm get-parameter \
  --name "${SSM_PREFIX}/root_token" \
  --with-decryption \
  --query Parameter.Value \
  --output text)"

export VAULT_TOKEN="${ROOT_TOKEN}"

vault kv put sample-secrets/demo/more key="value"
vault kv put sample-secrets/demo/api api_key="abcd1234"

echo "Seeded secrets into ${VAULT_ADDR}."
