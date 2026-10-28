#!/usr/bin/env bash
# A menu for phones: everything is done by typing a digit.
set -uo pipefail
cd "$(dirname "$0")"
source credentials.sh
if [ -f .cloudmaze.env ]; then source .cloudmaze.env; [ -n "${REGION:-}" ] && export AWS_REGION="$REGION"; fi
# Ask once here, so the steps below reuse the same login.
ensure_aws_credentials || exit 1

stolen_status() {
  [ -f .cloudmaze.env ] && [ -f .stolen-url ] || return 0
  source .cloudmaze.env
  local id closed
  id=$(sed -E 's#.*/v1/([0-9a-f]+)/orders#\1#' .stolen-url)
  closed=$(aws dynamodb get-item --table-name "$TABLE" --key '{"pk":{"S":"orders-api"}}' \
    --query "Item.closed.M.\"$id\"" --output text 2>/dev/null)
  if [ -n "$closed" ] && [ "$closed" != "None" ]; then
    echo "Stolen path $id: CLOSED. Choose 4 and attack now."
  else
    echo "Stolen path $id: still open. Wait a little longer before attacking."
  fi
}

while true; do
  echo
  echo "========== Cloud Maze =========="
  echo "Account: $AWS_ACCOUNT_ID, region $(aws_region)"
  if [ -f .cloudmaze.env ]; then echo "Status: installed"; stolen_status; else echo "Status: not installed"; fi
  echo
  echo "  1  Install"
  echo "  2  Run the authorized client (6 min)"
  echo "  3  Attacker: steal the current path"
  echo "  4  Attacker: attack with the stolen path"
  echo "  5  Attacker: try a decoy"
  echo "  6  Attacker: guess a path"
  echo "  7  Remove everything"
  echo "  0  Exit the menu"
  echo
  read -rp "Choose a number: " choice
  echo
  case "$choice" in
    1) read -rp "Your e-mail for alarms: " email
       [ -n "$email" ] && ./deploy.sh "$email" ;;
    2) ./client.sh 6 ;;
    3) ./attacker.sh steal ;;
    4) ./attacker.sh attack ;;
    5) ./attacker.sh decoy ;;
    6) ./attacker.sh guess ;;
    7) read -rp "Remove everything in AWS? Type y for yes: " yes
       [ "$yes" = "y" ] && ./destroy.sh ;;
    0) echo "Start the menu again with:  cloud-maze/cm"; exit 0 ;;
    *) echo "Type a number from 0 to 7." ;;
  esac
done
