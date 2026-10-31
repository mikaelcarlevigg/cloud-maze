#!/usr/bin/env bash
# Installs Cloud Maze in your AWS account.  Usage:  ./deploy.sh you@example.com [minutes]
set -euo pipefail
cd "$(dirname "$0")"

EMAIL="${1:?Give your e-mail address: ./deploy.sh you@example.com}"
INTERVAL="${2:-2}"
STACK="${STACK:-cloud-maze}"

source credentials.sh
ensure_aws_credentials || exit 1
REGION="$(aws_region)"

echo "Installing the stack $STACK in account $AWS_ACCOUNT_ID, region $REGION."
read -rp "Is that right? Type y to continue: " yes
[ "$yes" = "y" ] || { echo "Cancelled."; exit 1; }
# Optional LLM, any OpenAI-compatible API:
#   LLM_BASE_URL=https://api.groq.com/openai/v1 LLM_MODEL=llama-3.3-70b-versatile ./deploy.sh you@example.com
# Or Amazon Bedrock, with no key:
#   LLM_PROVIDER=bedrock LLM_MODEL=<model or inference profile id> ./deploy.sh you@example.com
PARAMS=("AlarmEmail=$EMAIL" "IntervalMinutes=$INTERVAL")
if [ "${LLM_PROVIDER:-}" = "bedrock" ]; then
  PARAMS+=("LlmProvider=bedrock" "LlmModel=${LLM_MODEL:?Set LLM_MODEL to a Bedrock model or inference profile id}")
elif [ -n "${LLM_BASE_URL:-}" ]; then
  [ -n "${LLM_API_KEY:-}" ] || read -rsp "API key for the LLM (hidden as you type): " LLM_API_KEY; echo
  PARAMS+=("LlmBaseUrl=$LLM_BASE_URL" "LlmModel=${LLM_MODEL:?Set LLM_MODEL}" "LlmApiKey=$LLM_API_KEY")
fi

aws cloudformation deploy \
  --stack-name "$STACK" \
  --template-file template.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides "${PARAMS[@]}"

output() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

# Start the maze right away instead of waiting for the first scheduled move.
aws lambda invoke --function-name "$(output RotatorFunction)" /tmp/cloudmaze-rotate.json >/dev/null

cat > .cloudmaze.env <<ENV
STACK=$STACK
REGION=$REGION
ACCOUNT=$AWS_ACCOUNT_ID
API=$(output ApiEndpoint)
MAP_FUNCTION=$(output MapFunction)
TABLE=$(output StateTable)
ENV

echo
echo "Done. The maze is running and the path moves every $INTERVAL minutes."
echo
echo "Control panel for your phone: $(output PanelUrl)"
echo
echo "1. Open the e-mail from AWS Notifications and tap 'Confirm subscription'."
echo "   Otherwise no alarms arrive."
echo "2. Start the authorized client:    ./client.sh"
echo "3. Play the attacker:              ./attacker.sh steal"
echo "4. Remove everything when done:    ./destroy.sh"
