#!/usr/bin/env bash
# En meny för mobilen: allt görs genom att skriva en siffra.
set -uo pipefail
cd "$(dirname "$0")"

stolen_status() {
  [ -f .cloudmaze.env ] && [ -f .stolen-url ] || return 0
  source .cloudmaze.env
  local id closed
  id=$(sed -E 's#.*/v1/([0-9a-f]+)/orders#\1#' .stolen-url)
  closed=$(aws dynamodb get-item --table-name "$TABLE" --key '{"pk":{"S":"orders-api"}}' \
    --query "Item.closed.M.\"$id\"" --output text 2>/dev/null)
  if [ -n "$closed" ] && [ "$closed" != "None" ]; then
    echo "Stulen väg $id: STÄNGD. Välj 4 och angrip nu."
  else
    echo "Stulen väg $id: fortfarande öppen. Vänta lite till innan du angriper."
  fi
}

while true; do
  echo
  echo "========== Cloud Maze =========="
  if [ -f .cloudmaze.env ]; then echo "Status: installerad"; stolen_status; else echo "Status: inte installerad"; fi
  echo
  echo "  1  Installera"
  echo "  2  Kör behörig klient (6 min)"
  echo "  3  Angripare: stjäl vägen som gäller nu"
  echo "  4  Angripare: angrip med stulen väg"
  echo "  5  Angripare: prova lockbete"
  echo "  6  Angripare: gissa en väg"
  echo "  7  Ta bort allt"
  echo "  0  Avsluta menyn"
  echo
  read -rp "Välj siffra: " choice
  echo
  case "$choice" in
    1) read -rp "Din e-post för larm: " email
       [ -n "$email" ] && ./deploy.sh "$email" ;;
    2) ./client.sh 6 ;;
    3) ./attacker.sh steal ;;
    4) ./attacker.sh attack ;;
    5) ./attacker.sh decoy ;;
    6) ./attacker.sh guess ;;
    7) read -rp "Ta bort allt i AWS? Skriv j för ja: " yes
       [ "$yes" = "j" ] && ./destroy.sh ;;
    0) echo "Starta menyn igen med:  cloud-maze/cm"; exit 0 ;;
    *) echo "Skriv en siffra mellan 0 och 7." ;;
  esac
done
