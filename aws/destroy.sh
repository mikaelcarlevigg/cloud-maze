#!/usr/bin/env bash
# Removes everything deploy.sh created.
set -euo pipefail
cd "$(dirname "$0")"
STACK="${STACK:-cloud-maze}"
source credentials.sh
if [ -f .cloudmaze.env ]; then source .cloudmaze.env; [ -n "${REGION:-}" ] && export AWS_REGION="$REGION"; fi
ensure_aws_credentials || exit 1
echo "Removing the stack $STACK in account $AWS_ACCOUNT_ID, region $(aws_region) ..."
aws cloudformation delete-stack --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --stack-name "$STACK"
rm -f .cloudmaze.env .stolen-url
echo "Done. Everything has been removed."
