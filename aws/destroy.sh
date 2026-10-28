#!/usr/bin/env bash
# Tar bort allt som deploy.sh skapade.
set -euo pipefail
cd "$(dirname "$0")"
STACK="${STACK:-cloud-maze}"
source credentials.sh
if [ -f .cloudmaze.env ]; then source .cloudmaze.env; [ -n "${REGION:-}" ] && export AWS_REGION="$REGION"; fi
ensure_aws_credentials || exit 1
echo "Tar bort stacken $STACK i konto $AWS_ACCOUNT_ID, region $(aws_region) ..."
aws cloudformation delete-stack --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --stack-name "$STACK"
rm -f .cloudmaze.env .stolen-url
echo "Klart. Allt är borttaget."
