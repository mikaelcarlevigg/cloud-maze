#!/usr/bin/env bash
# An authorized client. Fetches the map with its IAM identity and always calls the current path.
# Usage:  ./client.sh [minutes]   (6 minutes by default, stop earlier with Ctrl+C)
set -uo pipefail
cd "$(dirname "$0")"
source .cloudmaze.env
source credentials.sh
if [ -n "${REGION:-}" ]; then export AWS_REGION="$REGION"; fi
ensure_aws_credentials || exit 1
if [ -n "${ACCOUNT:-}" ] && [ "$AWS_ACCOUNT_ID" != "$ACCOUNT" ]; then
  echo "You are signed in to account $AWS_ACCOUNT_ID, but Cloud Maze is installed in $ACCOUNT."
  exit 1
fi

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
  pass=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pass"])' "$MAP")
}

summary() { echo; echo "Client: $ok requests succeeded, $failed failed."; }
trap 'summary; exit 0' INT

echo "Authorized client started. Calling the service every 10 seconds for ${1:-6} minutes."
while [ "$(date +%s)" -lt "$end" ]; do
  if [ "$(date +%s)" -ge "$refresh_at" ]; then fetch_map; fi
  body=$(curl -s -w '\n%{http_code}' -H "X-Maze-Pass: $pass" "$url")
  code=$(tail -n1 <<<"$body")
  note=""
  count=$(head -n1 <<<"$body" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("orders", [])))' 2>/dev/null || echo 0)
  # The real orders are from Nordvind AB. With a valid pass the client always gets them, even if
  # its IP address is in the shadow world.
  grep -q "Nordvind AB" <<<"$body" || [ "$count" = 0 ] || note="  <- FAKE orders: the pass was not accepted"
  [ -n "$last" ] && [ "$url" != "$last" ] && note="  <- new path from the map$note"
  if [ "$code" = "200" ] && [ "$count" -gt 0 ]; then
    ok=$((ok + 1)); echo "$(date +%H:%M:%S)  OK   $url  ($count orders)$note"
  else
    failed=$((failed + 1)); echo "$(date +%H:%M:%S)  ERROR  $url  (answer $code)"
    refresh_at=0
  fi
  last="$url"
  sleep 10
done
summary
