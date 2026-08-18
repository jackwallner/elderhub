#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source ~/.aging_credentials

API="https://api.supabase.com/v1/projects/$AGING_SUPABASE_PROJECT_REF/config/auth"

current="$(curl -sS "$API" -H "Authorization: Bearer $AGING_SUPABASE_ACCESS_TOKEN")"

body="$(python3 - "$current" <<'PY'
import json
import sys

config = json.loads(sys.argv[1])
urls = [url.strip() for url in config.get("uri_allow_list", "").split(",") if url.strip()]
if "elderhub://auth" not in urls:
    urls.append("elderhub://auth")

print(json.dumps({
    "uri_allow_list": ",".join(urls),
}))
PY
)"

response="$(curl -sS -X PATCH "$API" \
  -H "Authorization: Bearer $AGING_SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$body")"

if ! jq -e '.uri_allow_list | split(",") | index("elderhub://auth")' >/dev/null <<<"$response"; then
  echo "error: hosted auth redirect was not updated" >&2
  jq -r '.message // .error // "unknown response"' <<<"$response" >&2
  exit 1
fi

echo "==> Elderhub email sign-in redirect configured"
