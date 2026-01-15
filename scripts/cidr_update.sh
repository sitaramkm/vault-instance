#!/bin/bash
set -euo pipefail

# Usage:
#   ./cidr_update.sh <aws_profile> <cidr1> [cidr2 ...]
#
# Example:
#   ./cidr_update.sh my-corp-profile 203.0.113.10/32 198.51.100.0/24

AWS_PROFILE="$1"
shift

if [ $# -lt 1 ]; then
  echo "Usage: ./cidr_update.sh <aws_profile> <cidr1> [cidr2 ...]"
  exit 1
fi

export AWS_PROFILE

CIDRS_JSON=$(python3 - <<PY
import json, sys
print(json.dumps(sys.argv[1:]))
PY
"$@")

terraform apply -var "allowed_additional_cidrs=${CIDRS_JSON}"
