#!/usr/bin/env bash
# Installerar Cloud Maze i ditt AWS-konto.  Användning:  ./deploy.sh din@epost.se [minuter]
set -euo pipefail
cd "$(dirname "$0")"

EMAIL="${1:?Ange din e-postadress: ./deploy.sh din@epost.se}"
INTERVAL="${2:-2}"
STACK="${STACK:-cloud-maze}"

source credentials.sh
ensure_aws_credentials || exit 1
REGION="$(aws_region)"

echo "Installerar stacken $STACK i konto $AWS_ACCOUNT_ID, region $REGION."
read -rp "Stämmer det? Skriv j för att fortsätta: " yes
[ "$yes" = "j" ] || { echo "Avbrutet."; exit 1; }
# Optional LLM, any OpenAI-compatible API:
#   LLM_BASE_URL=https://api.groq.com/openai/v1 LLM_MODEL=llama-3.3-70b-versatile ./deploy.sh din@epost.se
PARAMS=("AlarmEmail=$EMAIL" "IntervalMinutes=$INTERVAL")
if [ -n "${LLM_BASE_URL:-}" ]; then
  [ -n "${LLM_API_KEY:-}" ] || read -rsp "API-nyckel för LLM:en (syns inte när du skriver): " LLM_API_KEY; echo
  PARAMS+=("LlmBaseUrl=$LLM_BASE_URL" "LlmModel=${LLM_MODEL:?Ange LLM_MODEL}" "LlmApiKey=$LLM_API_KEY")
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
echo "Klart. Labyrinten är igång och vägen flyttas var $INTERVAL:e minut."
echo
echo "Kontrollpanel för mobilen: $(output PanelUrl)"
echo
echo "1. Öppna mejlet från AWS Notifications och tryck på 'Confirm subscription'."
echo "   Annars kommer inga larm fram."
echo "2. Starta den behöriga klienten:   ./client.sh"
echo "3. Spela angripare:                ./attacker.sh steal"
echo "4. Ta bort allt när du är klar:    ./destroy.sh"
