#!/bin/bash
set -e
cd "$(dirname "$0")/.."

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  CREDS="${HOME}/.baseball_credentials"
  [[ -f "$CREDS" ]] && source "$CREDS"
fi

if [[ -z "${ASC_API_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_KEY_PATH:-}" ]]; then
  echo "error: App Store Connect credentials are not configured" >&2
  exit 1
fi

if [[ -d fastlane/metadata ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP="fastlane/metadata.bak.${STAMP}"
  cp -R fastlane/metadata "$BACKUP"
  echo "snapshot: $BACKUP"
fi

TMPKEY="$(mktemp -t elderhub_asc_api_key.XXXXXX.json)"
trap 'rm -f "$TMPKEY"' EXIT
P8_CONTENTS="$(<"$ASC_KEY_PATH")"
python3 - "$ASC_API_KEY_ID" "$ASC_ISSUER_ID" "$P8_CONTENTS" "$TMPKEY" <<'PY'
import json
import sys

key_id, issuer_id, key, output = sys.argv[1:5]
with open(output, "w", encoding="utf-8") as handle:
    json.dump({"key_id": key_id, "issuer_id": issuer_id, "key": key, "in_house": False}, handle)
PY

EXTRA=()
if [[ -n "${ASC_APP_VERSION:-}" ]]; then
  EXTRA+=(--app_version "$ASC_APP_VERSION")
fi

exec "$(dirname "$0")/fastlane-bin.sh" deliver download_metadata \
  --api_key_path "$TMPKEY" \
  --metadata_path ./fastlane/metadata \
  --force true \
  --skip_screenshots true \
  "${EXTRA[@]}" \
  "$@"
