#!/usr/bin/env bash
# Tar bort allt som deploy.sh skapade.
set -euo pipefail
cd "$(dirname "$0")"
STACK="${STACK:-cloud-maze}"
echo "Tar bort stacken $STACK ..."
aws cloudformation delete-stack --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --stack-name "$STACK"
rm -f .cloudmaze.env .stolen-url
echo "Klart. Allt är borttaget."
