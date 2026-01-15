#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ------------------------------------------------------------
# Load environment
# ------------------------------------------------------------

if [[ ! -f "${ROOT_DIR}/common.env" ]]; then
  echo "ERROR: common.env not found"
  exit 1
fi
source "${ROOT_DIR}/common.env"

if [[ -f "${ROOT_DIR}/aws.env" ]]; then
  source "${ROOT_DIR}/aws.env"
fi

: "${RESOURCE_PREFIX:?RESOURCE_PREFIX must be set in common.env}"

if [[ -n "${AWS_PROFILE:-}" ]]; then
  export AWS_PROFILE
fi

if [[ -n "${AWS_REGION:-}" ]]; then
  export AWS_REGION
  export AWS_DEFAULT_REGION="${AWS_REGION}"
fi

# ------------------------------------------------------------
# Validate AWS access
# ------------------------------------------------------------

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS CLI not authenticated"
  echo "Run 'aws sso login' or configure credentials"
  exit 1
fi

# ------------------------------------------------------------
# Token retrieval
# ------------------------------------------------------------

WHAT="${1:-all}"
PREFIX="/${RESOURCE_PREFIX}-ssm"

get_token() {
  local name="$1"
  aws ssm get-parameter \
    --name "${PREFIX}/${name}" \
    --with-decryption \
    --query Parameter.Value \
    --output text
}

case "${WHAT}" in
  root)
    echo "ROOT token:"
    get_token "root_token"
    ;;
  demo)
    echo "DEMO token:"
    get_token "demo_token"
    ;;
  all)
    echo "ROOT token:"
    get_token "root_token"
    echo
    echo "DEMO token:"
    get_token "demo_token"
    ;;
  *)
    echo "Usage:"
    echo "  ./scripts/tokens.sh"
    echo "  ./scripts/tokens.sh root"
    echo "  ./scripts/tokens.sh demo"
    exit 1
    ;;
esac
