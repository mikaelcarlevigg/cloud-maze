#!/usr/bin/env bash
# En behörig klient. Hämtar kartan med sin IAM-identitet och anropar alltid aktuell väg.
# Användning:  ./client.sh [minuter]   (standard 6 minuter, avsluta tidigare med Ctrl+C)
set -uo pipefail
cd "$(dirname "$0")"
source .cloudmaze.env

MAP=/tmp/cloudmaze-map.json
refresh_at=0
last=""
ok=0
failed=0
end=$(( $(date +%s) + ${1:-6} * 60 ))

fetch_map() {
  aws lambda invoke --function-name "$MAP_FUNCTION" "$MAP" >/dev/null
  url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$MAP")
  refresh_at=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["refresh_at"])' "$MAP")
}

summary() { echo; echo "Klienten: $ok lyckade, $failed misslyckade anrop."; }
trap 'summary; exit 0' INT

echo "Behörig klient startad. Anropar tjänsten var 10:e sekund i ${1:-6} minuter."
while [ "$(date +%s)" -lt "$end" ]; do
  if [ "$(date +%s)" -ge "$refresh_at" ]; then fetch_map; fi
  body=$(curl -s -w '\n%{http_code}' "$url")
  code=$(tail -n1 <<<"$body")
  count=$(head -n1 <<<"$body" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("orders", [])))' 2>/dev/null || echo 0)
  note=""
  [ -n "$last" ] && [ "$url" != "$last" ] && note="  <- ny väg från kartan"
  if [ "$code" = "200" ] && [ "$count" -gt 0 ]; then
    ok=$((ok + 1)); echo "$(date +%H:%M:%S)  OK   $url  ($count ordrar)$note"
  else
    failed=$((failed + 1)); echo "$(date +%H:%M:%S)  FEL  $url  (svar $code)"
    refresh_at=0
  fi
  last="$url"
  sleep 10
done
summary
