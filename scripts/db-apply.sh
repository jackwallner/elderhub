#!/usr/bin/env bash
# Apply the migrations in supabase/migrations to the real Supabase project.
#
# Uses the Management API's query endpoint rather than `supabase db push`, so it
# needs only a personal access token and no database password, and it does not
# touch the CLI's stored login (which belongs to a different Supabase account
# that owns Bond and Sports).
#
#   ./scripts/db-apply.sh            # apply every migration not yet recorded
#   ./scripts/db-apply.sh --dry-run  # list what would be applied
#   ./scripts/db-apply.sh --sql "select 1"   # run one ad-hoc statement
#
# Applied files are recorded in public.schema_migrations, so re-running is safe.
set -euo pipefail

# shellcheck source=/dev/null
source ~/.aging_credentials

REF="$AGING_SUPABASE_PROJECT_REF"
TOKEN="$AGING_SUPABASE_ACCESS_TOKEN"
API="https://api.supabase.com/v1/projects/$REF/database/query"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIG="$ROOT/supabase/migrations"

run_sql() {
  local sql="$1"
  local body
  body="$(python3 -c 'import json,sys; print(json.dumps({"query": sys.stdin.read()}))' <<<"$sql")"
  curl -sS -X POST "$API" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$body"
}

fail_if_error() {
  local response="$1" label="$2"
  if python3 - "$response" <<'PY'
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(data, dict) and ("message" in data or "error" in data) else 1)
PY
  then
    echo "FAILED: $label" >&2
    echo "$response" >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--sql" ]]; then
  run_sql "$2"
  echo
  exit 0
fi

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Ledger. Deliberately not the CLI's supabase_migrations.schema_migrations, so
# the two mechanisms can never half-agree about what is applied.
if ! $DRY_RUN; then
  out="$(run_sql "create table if not exists public.schema_migrations (
      filename   text primary key,
      applied_at timestamptz not null default now()
  );")"
  fail_if_error "$out" "create schema_migrations"
fi

applied="$(run_sql "select filename from public.schema_migrations order by filename;" \
  | python3 -c 'import json,sys
try:
    rows = json.load(sys.stdin)
    print("\n".join(r["filename"] for r in rows) if isinstance(rows, list) else "")
except Exception:
    print("")')"

for f in "$MIG"/*.sql; do
  name="$(basename "$f")"
  if grep -qxF "$name" <<<"$applied"; then
    echo "  = $name (already applied)"
    continue
  fi

  if $DRY_RUN; then
    echo "  + $name (would apply)"
    continue
  fi

  echo "  + $name"
  out="$(run_sql "$(cat "$f")")"
  fail_if_error "$out" "$name"

  out="$(run_sql "insert into public.schema_migrations (filename) values ('$name')
                  on conflict (filename) do nothing;")"
  fail_if_error "$out" "record $name"
done

echo "==> done"
