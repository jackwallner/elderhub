// Med List (Aging) — RevenueCat webhook.
//
// One person in the family buys through ordinary in-app purchase and the whole
// group is covered, which is the Life360 model. This function is the only writer
// of `group_billing`; the table has no client write policy at all, because a
// client that could PATCH it could give itself Plus.
//
// Why the entitlement lives on the group rather than being fanned out to each
// member as a RevenueCat promotional entitlement: fan-out means every join,
// leave and removal has to call RevenueCat's REST API, which creates a second
// source of truth that drifts and fails silently. A sibling with no Pro and no
// error anywhere is the failure mode, and it is invisible. With the entitlement
// on the group, membership changes run no billing code at all (§9).
//
// Configure in RevenueCat: Integrations → Webhooks → this URL, with an
// Authorization header matching REVENUECAT_WEBHOOK_SECRET.
//
// Secrets: REVENUECAT_WEBHOOK_SECRET.

import { createClient } from "jsr:@supabase/supabase-js@2";

/** Events that mean the customer should have access right now. */
const GRANTING = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "PRODUCT_CHANGE",
  "SUBSCRIPTION_EXTENDED",
  "TRANSFER",
]);

/** Events that end access immediately. A CANCELLATION does not: the customer
 *  keeps what they paid for until expiry, and EXPIRATION is what fires then. */
const REVOKING = new Set(["EXPIRATION", "REFUND", "SUBSCRIPTION_PAUSED"]);

const LIFETIME_PRODUCTS = new Set(["com.jackwallner.aging.pro.lifetime"]);

interface RCEvent {
  type: string;
  app_user_id: string;
  original_app_user_id?: string;
  product_id?: string;
  expiration_at_ms?: number | null;
  entitlement_ids?: string[] | null;
}

Deno.serve(async (req) => {
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (expected && req.headers.get("authorization") !== expected) {
    return new Response("unauthorized", { status: 401 });
  }

  const payload = await req.json().catch(() => null);
  const event: RCEvent | undefined = payload?.event;
  if (!event) return new Response("no event", { status: 400 });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // The app configures RevenueCat with the Supabase user id as app_user_id, so
  // this is a uuid. Anything else is an anonymous RevenueCat id from before
  // sign-in and has no group to credit yet.
  const userId = event.app_user_id;
  if (!/^[0-9a-f-]{36}$/i.test(userId)) {
    console.log(`Ignoring non-uuid app_user_id ${userId}`);
    return new Response(JSON.stringify({ ignored: "anonymous" }), {
      headers: { "content-type": "application/json" },
    });
  }

  // Whichever groups this person belongs to. In practice one; crediting all of
  // them is the right answer for the sandwich case, where the payer is the
  // organizer of their mother's group and a member of their children's.
  const { data: memberships, error: membershipError } = await supabase
    .from("group_members")
    .select("group_id")
    .eq("user_id", userId)
    .is("removed_at", null)
    .in("role", ["owner", "caregiver"]);

  if (membershipError) {
    console.error("membership lookup failed", membershipError);
    return new Response(JSON.stringify({ error: membershipError.message }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  if (!memberships?.length) {
    // Bought before joining a group. Nothing to write yet; the client's own
    // RevenueCat entitlement still unlocks their device, and the next event
    // (or a manual restore) lands after they have a group.
    return new Response(JSON.stringify({ ignored: "no group" }), {
      headers: { "content-type": "application/json" },
    });
  }

  const granting = GRANTING.has(event.type);
  const revoking = REVOKING.has(event.type);
  if (!granting && !revoking) {
    return new Response(JSON.stringify({ ignored: event.type }), {
      headers: { "content-type": "application/json" },
    });
  }

  const isLifetime = granting && LIFETIME_PRODUCTS.has(event.product_id ?? "");
  const expiresAt =
    granting && !isLifetime && event.expiration_at_ms
      ? new Date(event.expiration_at_ms).toISOString()
      : null;

  const rows = memberships.map((m) => ({
    group_id: m.group_id,
    entitlement: granting ? "plus" : "free",
    expires_at: expiresAt,
    is_lifetime: isLifetime,
    payer_user_id: granting ? userId : null,
    rc_app_user_id: event.original_app_user_id ?? userId,
    product_id: event.product_id ?? null,
  }));

  const { error } = await supabase
    .from("group_billing")
    .upsert(rows, { onConflict: "group_id" });

  if (error) {
    console.error("group_billing upsert failed", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(
    JSON.stringify({ type: event.type, groups: rows.length, plus: granting }),
    { headers: { "content-type": "application/json" } },
  );
});
