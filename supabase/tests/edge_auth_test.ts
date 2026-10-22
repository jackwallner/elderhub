// Execute the production handlers with a fake client and no network permission.
import { calls } from "./edge_client_stub.ts";

type Handler = (request: Request) => Promise<Response>;

async function loadHandler(slug: string): Promise<Handler> {
  const serve = Deno.serve;
  let handler: Handler | undefined;
  Reflect.set(Deno, "serve", (candidate: Handler) => { handler = candidate; return {}; });
  try {
    await import(new URL(`../../SupabaseFunctions/${slug}/index.ts`, import.meta.url).href);
  } finally {
    Reflect.set(Deno, "serve", serve);
  }
  if (!handler) throw new Error("handler was not registered");
  return handler;
}

function expectStatus(response: Response, expected: number): void {
  if (response.status !== expected) {
    throw new Error(`expected ${expected}, got ${response.status}; service operations: ${calls.join(", ")}`);
  }
}

function expectNoServiceCalls(): void {
  if (calls.length) throw new Error(`unauthorized service operations: ${calls.join(", ")}`);
}

Deno.test("webhook_without_secret_cannot_write_foreign_billing", async () => {
  Deno.env.set("SUPABASE_URL", "http://127.0.0.1:1");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role");
  Deno.env.delete("REVENUECAT_WEBHOOK_SECRET");
  const handler = await loadHandler("revenuecat-webhook");
  const request = (authorization?: string) => new Request("http://localhost/webhook", {
    method: "POST",
    headers: { "content-type": "application/json", ...(authorization ? { authorization } : {}) },
    body: JSON.stringify({ event: {
      type: "NON_RENEWING_PURCHASE",
      app_user_id: "11111111-1111-4111-8111-111111111111",
      product_id: "com.jackwallner.aging.pro.lifetime",
    } }),
  });
  calls.length = 0;
  expectStatus(await handler(request()), 503);
  expectNoServiceCalls();
  Deno.env.set("REVENUECAT_WEBHOOK_SECRET", "test-webhook-secret");
  expectStatus(await handler(request("wrong-secret")), 401);
  expectNoServiceCalls();
  expectStatus(await handler(request("test-webhook-secret")), 200);
  if (!calls.includes("write:group_billing")) throw new Error("authorized webhook must still write billing");
});

Deno.test("escalation_requires_service_authorization_before_cross_circle_writes", async () => {
  Deno.env.set("SUPABASE_URL", "http://127.0.0.1:1");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role");
  for (const key of ["APNS_KEY_ID", "APNS_TEAM_ID", "APNS_BUNDLE_ID", "APNS_PRIVATE_KEY"]) Deno.env.delete(key);
  const handler = await loadHandler("escalate-check-ins");
  calls.length = 0;
  expectStatus(await handler(new Request("http://localhost/escalate", {
    headers: { authorization: "Bearer test-anon-jwt" },
  })), 401);
  expectNoServiceCalls();
  expectStatus(await handler(new Request("http://localhost/escalate")), 401);
  expectNoServiceCalls();
  Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
  expectStatus(await handler(new Request("http://localhost/escalate")), 503);
  expectNoServiceCalls();
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role");
  expectStatus(await handler(new Request("http://localhost/escalate", {
    headers: { authorization: "Bearer test-service-role" },
  })), 503);
  if (!calls.includes("rpc:queue_check_in_notices")) throw new Error("authorized worker must still queue notices");
  Deno.env.set("ESCALATION_SERVICE_KEY", "test-cron-jwt");
  calls.length = 0;
  expectStatus(await handler(new Request("http://localhost/escalate", {
    headers: { authorization: "Bearer test-cron-jwt" },
  })), 503);
  if (!calls.includes("rpc:queue_check_in_notices")) throw new Error("the cron's key must still queue notices");
  calls.length = 0;
  expectStatus(await handler(new Request("http://localhost/escalate", {
    headers: { authorization: "Bearer test-anon-jwt" },
  })), 401);
  expectNoServiceCalls();
  Deno.env.delete("ESCALATION_SERVICE_KEY");
});
