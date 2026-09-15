import assert from "node:assert";
import crypto from "node:crypto";
import fs from "node:fs";

// Tests must never need, read, or risk leaking the seller's production key.
process.env.LICENCE_PRIVATE_KEY = crypto.randomBytes(32).toString("base64");
process.env.DB_PATH = "/tmp/jendela-test.db";
process.env.WEBHOOK_SECRET = "test-secret";
process.env.PORT = "8788";
process.env.SITE_URL = "http://localhost:8788";
process.env.ADMIN_EMAIL = "owner@example.com";
fs.rmSync("/tmp/jendela-test.db", { force: true });
fs.rmSync("/tmp/jendela-test.db-wal", { force: true });
fs.rmSync("/tmp/jendela-test.db-shm", { force: true });

const { server, db } = await import("./src/server.mjs");
await new Promise((r) => server.listen(8788, r));
const base = "http://localhost:8788";

let passed = 0, failed = 0;
async function check(name, fn) {
  try { await fn(); console.log(`  ✓ ${name}`); passed++; }
  catch (e) { console.log(`  ✗ ${name}\n      ${e.message}`); failed++; }
}

const sign = (body) => crypto.createHmac("sha256", "test-secret").update(body).digest("hex");
const order = (email, id, event = "order_created") =>
  JSON.stringify({ meta: { event_name: event }, data: { id, attributes: { user_email: email, total: 2900, currency: "USD" } } });

await check("an unsigned webhook is refused", async () => {
  const res = await fetch(`${base}/api/webhooks/payment`, {
    method: "POST", body: order("a@b.com", "1"),
  });
  assert.equal(res.status, 401);
});

await check("a wrongly signed webhook is refused", async () => {
  const body = order("a@b.com", "1");
  const res = await fetch(`${base}/api/webhooks/payment`, {
    method: "POST", headers: { "x-signature": sign("something else") }, body,
  });
  assert.equal(res.status, 401);
});

let issuedKey;
await check("a signed order issues a licence", async () => {
  const body = order("buyer@example.com", "ord_1");
  const res = await fetch(`${base}/api/webhooks/payment`, {
    method: "POST", headers: { "x-signature": sign(body) }, body,
  });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).action, "issued");
  const row = db.prepare("SELECT key FROM licences WHERE order_ref = 'ord_1'").get();
  assert.ok(row?.key?.startsWith("JNDL1."));
  issuedKey = row.key;
});

await check("a retried webhook does not issue a second licence", async () => {
  const body = order("buyer@example.com", "ord_1");
  const res = await fetch(`${base}/api/webhooks/payment`, {
    method: "POST", headers: { "x-signature": sign(body) }, body,
  });
  assert.equal((await res.json()).action, "already issued");
  const count = db.prepare("SELECT COUNT(*) AS n FROM licences").get().n;
  assert.equal(count, 1, `expected one licence, found ${count}`);
});

await check("a refund marks the licence refunded", async () => {
  const body = order("buyer@example.com", "ord_1", "order_refunded");
  await fetch(`${base}/api/webhooks/payment`, {
    method: "POST", headers: { "x-signature": sign(body) }, body,
  });
  const row = db.prepare("SELECT status FROM licences WHERE order_ref = 'ord_1'").get();
  assert.equal(row.status, "refunded");
});

await check("sign-in reveals nothing about who has an account", async () => {
  const known = await (await fetch(`${base}/api/auth/request`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "buyer@example.com" }),
  })).json();
  const unknown = await (await fetch(`${base}/api/auth/request`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "nobody@example.com" }),
  })).json();
  assert.deepEqual(known, unknown);
});

await check("a bad email is rejected", async () => {
  const res = await fetch(`${base}/api/auth/request`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "not-an-email" }),
  });
  assert.equal(res.status, 400);
});

await check("a magic link signs you in, once only", async () => {
  const row = db.prepare("SELECT token FROM login_tokens WHERE email = 'buyer@example.com' AND used_at IS NULL ORDER BY rowid DESC").get();
  const first = await fetch(`${base}/api/auth/verify?token=${row.token}`, { redirect: "manual" });
  assert.equal(first.status, 302);
  const cookie = first.headers.get("set-cookie");
  assert.ok(cookie?.includes("HttpOnly"), "session cookie must be HttpOnly");

  const again = await fetch(`${base}/api/auth/verify?token=${row.token}`, { redirect: "manual" });
  assert.ok(again.headers.get("location").includes("error"), "a used link must not work twice");

  const me = await fetch(`${base}/api/me`, { headers: { cookie: cookie.split(";")[0] } });
  assert.equal((await me.json()).email, "buyer@example.com");
});

await check("an expired link is refused", async () => {
  const t = "expired-token";
  db.prepare("INSERT INTO login_tokens (token, email, created_at, expires_at) VALUES (?,?,?,?)")
    .run(t, "buyer@example.com", 0, 1);
  const res = await fetch(`${base}/api/auth/verify?token=${t}`, { redirect: "manual" });
  assert.ok(res.headers.get("location").includes("error"));
});

await check("the account page needs a session", async () => {
  assert.equal((await fetch(`${base}/api/me`)).status, 401);
});

await check("analytics record counts, not people", async () => {
  const columns = db.prepare("PRAGMA table_info(events)").all().map((c) => c.name);
  for (const forbidden of ["ip", "user_agent", "email", "customer_id"]) {
    assert.ok(!columns.includes(forbidden), `events table stores ${forbidden}`);
  }
});


// ------------------------------------------------------------------ admin
async function sessionFor(email) {
  await fetch(`${base}/api/auth/request`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email }),
  });
  const row = db.prepare("SELECT token FROM login_tokens WHERE email = ? AND used_at IS NULL ORDER BY rowid DESC").get(email);
  const res = await fetch(`${base}/api/auth/verify?token=${row.token}`, { redirect: "manual" });
  const cookie = res.headers.get("set-cookie");
  assert.ok(cookie, `no session cookie returned when signing in as ${email}`);
  return cookie.split(";")[0];
}

await check("a signed-out visitor cannot reach admin", async () => {
  for (const path of ["/api/admin/stats", "/api/admin/customers"]) {
    assert.equal((await fetch(`${base}${path}`)).status, 403, `${path} was reachable`);
  }
});

await check("an ordinary customer cannot reach admin", async () => {
  const cookie = await sessionFor("buyer@example.com");
  const res = await fetch(`${base}/api/admin/stats`, { headers: { cookie } });
  assert.equal(res.status, 403, "a paying customer could read the dashboard");
  const issue = await fetch(`${base}/api/admin/licence/issue`, {
    method: "POST", headers: { cookie, "content-type": "application/json" },
    body: JSON.stringify({ email: "free@rider.com" }),
  });
  assert.equal(issue.status, 403, "a customer could mint themselves a licence");
});

let adminCookie;
await check("the named admin can read the dashboard", async () => {
  adminCookie = await sessionFor("owner@example.com");
  const res = await fetch(`${base}/api/admin/stats`, { headers: { cookie: adminCookie } });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(typeof body.totals.customers === "number");
  assert.equal(body.downloads.length, 14, "expected a fortnight of daily download counts");
});

await check("admin can issue and revoke a licence", async () => {
  const created = await (await fetch(`${base}/api/admin/licence/issue`, {
    method: "POST", headers: { cookie: adminCookie, "content-type": "application/json" },
    body: JSON.stringify({ email: "comped@example.com", note: "review copy" }),
  })).json();
  assert.ok(created.key.startsWith("JNDL1."));

  const found = db.prepare(`SELECT l.id, l.status FROM licences l
    JOIN customers c ON c.id = l.customer_id WHERE c.email = 'comped@example.com'`).get();
  assert.equal(found.status, "active");

  await fetch(`${base}/api/admin/licence/revoke`, {
    method: "POST", headers: { cookie: adminCookie, "content-type": "application/json" },
    body: JSON.stringify({ id: found.id }),
  });
  assert.equal(db.prepare("SELECT status FROM licences WHERE id = ?").get(found.id).status, "revoked");
});

await check("search finds a customer and their licences", async () => {
  const res = await fetch(`${base}/api/admin/customers?q=comped`, { headers: { cookie: adminCookie } });
  const { customers } = await res.json();
  assert.equal(customers.length, 1);
  assert.equal(customers[0].licences.length, 1);
});

console.log(`\n  ${passed} passed, ${failed} failed`);
fs.writeFileSync("/tmp/issued-licence.txt", issuedKey ?? "");
server.close();
process.exit(failed ? 1 : 0);
