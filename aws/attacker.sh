#!/usr/bin/env bash
# Spela angripare.
#   ./attacker.sh steal    Stjäl vägen som gäller nu, som om den hade läckt i en logg
#   ./attacker.sh attack   Angriper med den stulna vägen
#   ./attacker.sh decoy    Provar en väg från en läckt konfigfil (ett planterat lockbete)
#   ./attacker.sh guess    Gissar en väg
set -euo pipefail
cd "$(dirname "$0")"
source .cloudmaze.env
source credentials.sh
if [ -n "${REGION:-}" ]; then export AWS_REGION="$REGION"; fi
ensure_aws_credentials || exit 1
if [ -n "${ACCOUNT:-}" ] && [ "$AWS_ACCOUNT_ID" != "$ACCOUNT" ]; then
  echo "Du är inloggad i konto $AWS_ACCOUNT_ID, men Cloud Maze är installerat i $ACCOUNT."
  exit 1
fi

STOLEN=.stolen-url

state() {
  aws dynamodb get-item --table-name "$TABLE" --key '{"pk":{"S":"orders-api"}}' \
    --query "$1" --output text
}

hit() {
  echo "GET $1"
  curl -s -w '\n-> svar %{http_code}\n' "$1"
}

case "${1:-}" in
  steal)
    url="$API/v1/$(state Item.current.S)/orders"
    echo "$url" > "$STOLEN"
    echo "Du har stulit: $url"
    echo
    hit "$url"
    echo
    echo "Vägen fungerar nu. Vänta minst två flyttar (4-5 minuter med standardinställningen)"
    echo "och kör sedan:  ./attacker.sh attack"
    echo "Du kan också öppna adressen i mobilens webbläsare senare."
    ;;
  attack)
    [ -f "$STOLEN" ] || { echo "Stjäl en väg först: ./attacker.sh steal"; exit 1; }
    hit "$(cat "$STOLEN")"
    echo
    echo "Kommer ordrarna från Nordvind AB och Fjallkraft AB är vägen fortfarande öppen. Vänta lite till."
    echo "Andra kunder betyder att vägen är stängd: ordrarna är falska, din IP-adress är i"
    echo "skuggvärlden och ett larm har skickats till din e-post."
    ;;
  decoy)
    hit "$API/v1/$(state 'Item.decoys.L[0].S')/orders"
    echo
    echo "Den här vägen har aldrig funnits på någon karta. Kolla din e-post."
    ;;
  guess)
    hit "$API/v1/$(python3 -c 'import secrets; print(secrets.token_hex(4))')/orders"
    echo
    echo "En gissning ger bara 404 och inget larm."
    ;;
  *)
    sed -n '2,6p' attacker.sh | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
