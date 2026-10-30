#!/usr/bin/env bash
# Play the attacker.
#   ./attacker.sh steal    Steals a full request to the current path, pass included, as if it had leaked in a log
#   ./attacker.sh attack   Attacks with the stolen path
#   ./attacker.sh decoy    Tries a path from a leaked config file (a planted decoy)
#   ./attacker.sh guess    Guesses a path
set -euo pipefail
cd "$(dirname "$0")"
source .cloudmaze.env
source credentials.sh
if [ -n "${REGION:-}" ]; then export AWS_REGION="$REGION"; fi
ensure_aws_credentials || exit 1
if [ -n "${ACCOUNT:-}" ] && [ "$AWS_ACCOUNT_ID" != "$ACCOUNT" ]; then
  echo "You are signed in to account $AWS_ACCOUNT_ID, but Cloud Maze is installed in $ACCOUNT."
  exit 1
fi

STOLEN=.stolen-url

state() {
  aws dynamodb get-item --table-name "$TABLE" --key '{"pk":{"S":"orders-api"}}' \
    --query "$1" --output text
}

hit() {
  echo "GET $1"
  curl -s -w '\n-> answer %{http_code}\n' "$1"
}

case "${1:-}" in
  steal)
    url="$API/v1/$(state Item.current.S)/orders?pass=$(state Item.currentPass.S)"
    echo "$url" > "$STOLEN"
    echo "You have stolen: $url"
    echo
    hit "$url"
    echo
    echo "The stolen request works now. Wait at least two moves (4-5 minutes with the default setting)"
    echo "and then run:  ./attacker.sh attack"
    echo "You can also open the address in your phone's browser later."
    ;;
  attack)
    [ -f "$STOLEN" ] || { echo "Steal a path first: ./attacker.sh steal"; exit 1; }
    hit "$(cat "$STOLEN")"
    echo
    echo "If the orders are from Nordvind AB and Fjallkraft AB, the path is still open. Wait a little longer."
    echo "Other customers mean the path is closed: the orders are fake, your IP address is in the"
    echo "shadow world and an alarm has been sent to your e-mail."
    ;;
  decoy)
    hit "$API/v1/$(state 'Item.decoys.L[0].S')/orders"
    echo
    echo "This path was never on any map. Check your e-mail."
    ;;
  guess)
    hit "$API/v1/$(python3 -c 'import secrets; print(secrets.token_hex(4))')/orders"
    echo
    echo "A guess only gets a 404 and no alarm."
    ;;
  *)
    sed -n '2,6p' attacker.sh | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
