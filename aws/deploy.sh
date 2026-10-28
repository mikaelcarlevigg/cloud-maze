#!/usr/bin/env bash
# Installerar Cloud Maze i ditt AWS-konto.  Användning:  ./deploy.sh din@epost.se [minuter]
set -euo pipefail
cd "$(dirname "$0")"

EMAIL="${1:?Ange din e-postadress: ./deploy.sh din@epost.se}"
INTERVAL="${2:-2}"
STACK="${STACK:-cloud-maze}"

echo "Installerar stacken $STACK i region $(aws configure get region || echo "${AWS_REGION:-okänd}") ..."
aws cloudformation deploy \
  --stack-name "$STACK" \
  --template-file template.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides "AlarmEmail=$EMAIL" "IntervalMinutes=$INTERVAL"

output() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

# Start the maze right away instead of waiting for the first scheduled move.
aws lambda invoke --function-name "$(output RotatorFunction)" /tmp/cloudmaze-rotate.json >/dev/null

cat > .cloudmaze.env <<ENV
STACK=$STACK
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
