#!/usr/bin/env bash
# Deploy the two edge functions to the Aging Supabase project.
#
# The CLI's stored login belongs to a different Supabase account (the one that
# owns Bond and Sports), so this passes SUPABASE_ACCESS_TOKEN explicitly and
# never touches `supabase login`. Same reasoning as db-apply.sh.
#
#   ./scripts/deploy-functions.sh              # deploy both
#   ./scripts/deploy-functions.sh escalate-check-ins
#
# Neither function does anything useful until its secrets exist. Set them once:
#
#   export SUPABASE_ACCESS_TOKEN=... SUPABASE_PROJECT_REF=...
#   supabase secrets set --project-ref "$REF" \
#       APNS_TEAM_ID=... APNS_BUNDLE_ID=com.jackwallner.aging \
#       APNS_ENV=production REVENUECAT_WEBHOOK_SECRET=...
#
# The two APNs key secrets do NOT go in by hand. `cat`ing a .p8 into the CLI
# stores a key whose newlines may or may not have survived, and an App Store
# Connect key is the same kind of file as an APNs key, so the wrong one goes in
# silently. Use the script, which checks the key against Apple first:
#
#   ./scripts/configure-apns.py ~/Downloads/AuthKey_XXXXXXXXXX.p8
#
# And the two Vault secrets the cron job reads (see migration 0007):
#
#   ./scripts/db-apply.sh --sql "select vault.create_secret(
#       'https://<ref>.supabase.co/functions/v1/escalate-check-ins',
#       'escalation_function_url');"
#   ./scripts/db-apply.sh --sql "select vault.create_secret(
#       '<service-role-key>', 'escalation_service_key');"
set -euo pipefail

# shellcheck source=/dev/null
source ~/.aging_credentials

export SUPABASE_ACCESS_TOKEN="$AGING_SUPABASE_ACCESS_TOKEN"
REF="$AGING_SUPABASE_PROJECT_REF"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v supabase >/dev/null || {
  echo "supabase CLI not found: brew install supabase/tap/supabase" >&2
  exit 1
}

FUNCTIONS=("$@")
if [[ ${#FUNCTIONS[@]} -eq 0 ]]; then
  FUNCTIONS=(escalate-check-ins revenuecat-webhook)
fi

# The CLI expects supabase/functions/<slug>/index.ts. The sources live in
# SupabaseFunctions/ so they are not mistaken for something the migration
# tooling owns, so stage them where the CLI can see them.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/supabase/functions"

for fn in "${FUNCTIONS[@]}"; do
  src="$ROOT/SupabaseFunctions/$fn"
  [[ -d "$src" ]] || { echo "No such function: $fn" >&2; exit 1; }
  cp -R "$src" "$STAGE/supabase/functions/$fn"
done

cd "$STAGE"
for fn in "${FUNCTIONS[@]}"; do
  echo "==> deploying $fn"
  # The RevenueCat webhook authenticates with its own shared secret header, so
  # it must not sit behind Supabase's JWT check: RevenueCat does not send one.
  extra=()
  if [[ "$fn" == "revenuecat-webhook" ]]; then extra+=(--no-verify-jwt); fi
  # `${extra[@]+...}` because macOS ships bash 3.2, where `set -u` treats an
  # empty array expansion as an unbound variable and kills the deploy.
  supabase functions deploy "$fn" --project-ref "$REF" ${extra[@]+"${extra[@]}"}
done

echo "==> done"
