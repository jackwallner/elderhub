// Med List (Aging) — the pusher.
//
// Called every 15 minutes by pg_cron (migration 0007). It does three things:
// queues a notice for every recipient whose check-in window has passed with no
// press, collects every notice not yet delivered, and sends one APNs push per
// caregiver device.
//
// What it deliberately does not do: decide that anything is wrong. The push body
// is written by the database as a statement of fact ("Mom has not checked in
// today"), never an assessment and never a promise that help is coming. See
// docs/architecture.md I6. If a future version wants richer copy, it belongs in
// 0007's SQL where it stays identical across app versions, not here.
//
// Secrets (set with `supabase secrets set`, never committed):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY, APNS_ENV
//
// APNS_PRIVATE_KEY is the .p8 contents. Newlines survive the CLI badly, so a
// literal "\n" is accepted and unescaped below.

import { createClient } from "jsr:@supabase/supabase-js@2";

const APNS_HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

interface NoticeTarget {
  notice_id: string;
  title: string;
  body: string;
  apns_token: string;
}

// ---------------------------------------------------------------------------
// APNs provider token
//
// ES256 over {alg, kid} . {iss, iat}. Apple rejects tokens older than an hour
// and rate-limits minting, so it is cached for the life of the isolate.
// ---------------------------------------------------------------------------

let cachedToken: { value: string; mintedAt: number } | null = null;

/// Every secret a push needs, so the run can say which one is missing.
///
/// Checked up front rather than at the point of use. Before this, each of these
/// was read with a `!` deep inside the send loop, so an unset key surfaced as an
/// unhandled throw *after* the notices had been queued: the function 500ed, the
/// log said only "TypeError", and the next run fifteen minutes later did exactly
/// the same thing. The one notification this app promises to get right cannot
/// fail illegibly.
const APNS_SECRETS = [
  "APNS_KEY_ID",
  "APNS_TEAM_ID",
  "APNS_BUNDLE_ID",
  "APNS_PRIVATE_KEY",
] as const;

function missingSecrets(): string[] {
  return APNS_SECRETS.filter((name) => !(Deno.env.get(name) ?? "").trim());
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

function base64url(input: ArrayBuffer | string): string {
  const bytes =
    typeof input === "string"
      ? new TextEncoder().encode(input)
      : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importSigningKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // Apple's ceiling is one hour; refresh well inside it.
  if (cachedToken && now - cachedToken.mintedAt < 45 * 60) {
    return cachedToken.value;
  }

  const keyId = requireEnv("APNS_KEY_ID");
  const teamId = requireEnv("APNS_TEAM_ID");
  const pem = requireEnv("APNS_PRIVATE_KEY");

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const payload = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${payload}`;

  const key = await importSigningKey(pem);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  const token = `${signingInput}.${base64url(signature)}`;
  cachedToken = { value: token, mintedAt: now };
  return token;
}

// ---------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------

interface SendResult {
  ok: boolean;
  /** Apple says this token will never work again; stop keeping it. */
  dead: boolean;
}

async function send(
  deviceToken: string,
  title: string,
  body: string,
): Promise<SendResult> {
  const host =
    APNS_HOSTS[(Deno.env.get("APNS_ENV") ?? "production") as keyof typeof APNS_HOSTS] ??
    APNS_HOSTS.production;
  const bundleId = requireEnv("APNS_BUNDLE_ID");

  const response = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      // Time-sensitive would be defensible and is deliberately not used: this
      // is not an emergency and must not present itself as one.
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: { title, body },
        sound: "default",
        "interruption-level": "active",
      },
    }),
  });

  if (response.ok) return { ok: true, dead: false };

  const text = await response.text();
  const dead =
    response.status === 410 ||
    text.includes("BadDeviceToken") ||
    text.includes("Unregistered");
  console.error(`APNs ${response.status} for ${deviceToken.slice(0, 8)}…: ${text}`);
  return { ok: false, dead };
}

// ---------------------------------------------------------------------------

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: queued, error: queueError } = await supabase.rpc(
    "queue_check_in_notices",
  );
  if (queueError) {
    console.error("queue_check_in_notices failed", queueError);
    return new Response(JSON.stringify({ error: queueError.message }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  // Queued first, then this. A missed check-in is a fact worth recording even
  // on a project where the push cannot go out yet; the notices stay pending and
  // are delivered by the first run after the secrets land.
  const missing = missingSecrets();
  if (missing.length > 0) {
    console.error(
      `APNs is not configured, so nothing was sent. Missing: ${missing.join(", ")}`,
    );
    return new Response(
      JSON.stringify({ error: "apns_not_configured", missing, queued: queued ?? 0 }),
      { status: 503, headers: { "content-type": "application/json" } },
    );
  }

  const { data: targets, error: targetError } = await supabase.rpc(
    "pending_notices_with_targets",
  );
  if (targetError) {
    console.error("pending_notices_with_targets failed", targetError);
    return new Response(JSON.stringify({ error: targetError.message }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }

  const rows = (targets ?? []) as NoticeTarget[];
  const delivered = new Set<string>();
  const deadTokens = new Set<string>();

  for (const row of rows) {
    const result = await send(row.apns_token, row.title, row.body);
    if (result.ok) {
      delivered.add(row.notice_id);
    } else if (result.dead) {
      deadTokens.add(row.apns_token);
      // A notice whose only remaining audience is a dead token would otherwise
      // be retried every 15 minutes forever.
      delivered.add(row.notice_id);
    }
  }

  if (delivered.size > 0) {
    await supabase.rpc("mark_notices_delivered", { p_ids: [...delivered] });
  }
  for (const token of deadTokens) {
    await supabase.rpc("clear_apns_token", { p_token: token });
  }

  return new Response(
    JSON.stringify({
      queued: queued ?? 0,
      pushes: rows.length,
      delivered: delivered.size,
      cleared: deadTokens.size,
    }),
    { headers: { "content-type": "application/json" } },
  );
});
