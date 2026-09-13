import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { open, customerByEmail, record, now, today, token } from "./db.mjs";
import { mint } from "./licence.mjs";
import { send } from "./mail.mjs";
import { isAdmin, stats, search, issue, revoke } from "./admin.mjs";

const PORT = Number(process.env.PORT || 8787);
const SITE = process.env.SITE_URL || `http://localhost:${PORT}`;
// In production one process serves the site, the dashboard and the shared
// assets, so everything is same-origin and the session cookie just works.
const ROOTS = [
  process.env.WEB_ROOT || path.resolve("../web"),
  process.env.ADMIN_ROOT || path.resolve("../admin"),
  process.env.SHARED_ROOT || path.resolve("../shared"),
];
const WEB_ROOT = ROOTS[0];
const db = open();

const json = (res, code, body) => {
  res.writeHead(code, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
};

const readBody = (req) =>
  new Promise((resolve) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
  });

/// Sessions travel in an HttpOnly cookie: a token readable by JavaScript is one
/// cross-site script away from being someone else's licence.
function sessionCookie(value, maxAge = 60 * 60 * 24 * 60) {
  const secure = SITE.startsWith("https") ? " Secure;" : "";
  return `jendela_session=${value}; HttpOnly;${secure} SameSite=Lax; Path=/; Max-Age=${maxAge}`;
}

function currentCustomer(req) {
  const raw = req.headers.cookie || "";
  const match = raw.match(/jendela_session=([^;]+)/);
  if (!match) return null;
  const session = db
    .prepare("SELECT * FROM sessions WHERE token = ? AND expires_at > ?")
    .get(match[1], now());
  if (!session) return null;
  return db.prepare("SELECT * FROM customers WHERE id = ?").get(session.customer_id);
}

const routes = {
  /// Step one of signing in: no password to choose, forget or leak.
  "POST /api/auth/request": async (req, res) => {
    const { email } = JSON.parse((await readBody(req)).toString() || "{}");
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return json(res, 400, { error: "A valid email is required." });
    }
    const value = token();
    db.prepare(
      "INSERT INTO login_tokens (token, email, created_at, expires_at) VALUES (?, ?, ?, ?)"
    ).run(value, String(email).toLowerCase(), now(), now() + 900);

    const link = `${SITE}/api/auth/verify?token=${value}`;
    const result = await send({
      to: email,
      subject: "Your Jendela. sign-in link",
      text: `Open this link to sign in. It works once and expires in 15 minutes.\n\n${link}\n`,
    });
    // Always the same answer, so this cannot be used to discover who has an
    // account.
    json(res, 200, { ok: true, delivered: result.delivered });
  },

  "GET /api/auth/verify": (req, res, url) => {
    const value = url.searchParams.get("token");
    const row = value
      ? db.prepare("SELECT * FROM login_tokens WHERE token = ?").get(value)
      : null;
    if (!row || row.used_at || row.expires_at < now()) {
      res.writeHead(302, { location: "/account.html?error=link" });
      return res.end();
    }
    db.prepare("UPDATE login_tokens SET used_at = ? WHERE token = ?").run(now(), value);

    const customer = customerByEmail(db, row.email);
    const session = token();
    db.prepare(
      "INSERT INTO sessions (token, customer_id, created_at, expires_at) VALUES (?, ?, ?, ?)"
    ).run(session, customer.id, now(), now() + 60 * 60 * 24 * 60);

    res.writeHead(302, { location: "/account.html", "set-cookie": sessionCookie(session) });
    res.end();
  },

  "POST /api/auth/signout": (req, res) => {
    const match = (req.headers.cookie || "").match(/jendela_session=([^;]+)/);
    if (match) db.prepare("DELETE FROM sessions WHERE token = ?").run(match[1]);
    res.writeHead(200, { "set-cookie": sessionCookie("", 0), "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true }));
  },

  /// What the account page shows.
  "GET /api/me": (req, res) => {
    const customer = currentCustomer(req);
    if (!customer) return json(res, 401, { error: "Not signed in." });
    const licences = db
      .prepare("SELECT id, key, kind, status, created_at FROM licences WHERE customer_id = ? ORDER BY created_at DESC")
      .all(customer.id);
    json(res, 200, { email: customer.email, licences });
  },

  /// Payment provider callback. Lemon Squeezy and Paddle both sign the body;
  /// an unverified webhook would let anyone mint themselves a licence.
  "POST /api/webhooks/payment": async (req, res) => {
    const raw = await readBody(req);
    const secret = process.env.WEBHOOK_SECRET;
    if (!secret) return json(res, 503, { error: "Webhook secret not configured." });

    const signature =
      req.headers["x-signature"] || req.headers["x-event-signature"] || "";
    const expected = crypto.createHmac("sha256", secret).update(raw).digest("hex");
    const provided = Buffer.from(String(signature), "utf8");
    const computed = Buffer.from(expected, "utf8");
    if (
      provided.length !== computed.length ||
      !crypto.timingSafeEqual(provided, computed)
    ) {
      return json(res, 401, { error: "Bad signature." });
    }

    let event;
    try {
      event = JSON.parse(raw.toString());
    } catch {
      return json(res, 400, { error: "Bad payload." });
    }

    const kind = event.meta?.event_name || event.event_type || "";
    const data = event.data?.attributes || event.data || {};
    const email = data.user_email || data.email || data.customer_email;
    const orderRef = String(event.data?.id || data.order_id || data.id || "");

    if (/refund/i.test(kind)) {
      db.prepare("UPDATE licences SET status = 'refunded', revoked_at = ? WHERE order_ref = ?")
        .run(now(), orderRef);
      record(db, "refund");
      return json(res, 200, { ok: true, action: "refunded" });
    }

    if (!/order_created|subscription_created|payment_succeeded|completed/i.test(kind)) {
      return json(res, 200, { ok: true, action: "ignored" });
    }
    if (!email) return json(res, 400, { error: "No email on the order." });

    // Providers retry, so the same order must not mint a second licence.
    const existing = orderRef
      ? db.prepare("SELECT key FROM licences WHERE order_ref = ?").get(orderRef)
      : null;
    if (existing) return json(res, 200, { ok: true, action: "already issued" });

    const customer = customerByEmail(db, email);
    const licence = mint({ email: customer.email });
    db.prepare(
      `INSERT INTO licences (id, customer_id, key, kind, status, order_ref, amount, currency, created_at)
       VALUES (?, ?, ?, 'lifetime', 'active', ?, ?, ?, ?)`
    ).run(
      licence.id, customer.id, licence.key, orderRef || null,
      data.total ?? data.amount ?? null, data.currency ?? null, now()
    );
    record(db, "purchase");

    await send({
      to: customer.email,
      subject: "Your Jendela. licence",
      text:
        `Thank you. Here is your licence key:\n\n${licence.key}\n\n` +
        `Paste it into Jendela. → Settings → Licence. It is verified on your Mac, ` +
        `so it keeps working with no internet connection.\n\n` +
        `Your key is always available at ${SITE}/account.html\n`,
    });

    json(res, 200, { ok: true, action: "issued" });
  },

  "POST /api/licence/resend": async (req, res) => {
    const customer = currentCustomer(req);
    if (!customer) return json(res, 401, { error: "Not signed in." });
    const licence = db
      .prepare("SELECT key FROM licences WHERE customer_id = ? AND status = 'active' ORDER BY created_at DESC")
      .get(customer.id);
    if (!licence) return json(res, 404, { error: "No active licence." });
    await send({
      to: customer.email,
      subject: "Your Jendela. licence",
      text: `Here is your licence key again:\n\n${licence.key}\n`,
    });
    json(res, 200, { ok: true });
  },

  // ---------------------------------------------------------------- admin
  //
  // Every one of these re-checks admin on the request. Hiding the page would
  // not be security; the endpoints are the door.
  "GET /api/admin/stats": (req, res) => {
    const customer = currentCustomer(req);
    if (!isAdmin(customer)) return json(res, 403, { error: "Not allowed." });
    json(res, 200, stats(db));
  },

  "GET /api/admin/customers": (req, res, url) => {
    const customer = currentCustomer(req);
    if (!isAdmin(customer)) return json(res, 403, { error: "Not allowed." });
    json(res, 200, { customers: search(db, url.searchParams.get("q")) });
  },

  "POST /api/admin/licence/issue": async (req, res) => {
    const customer = currentCustomer(req);
    if (!isAdmin(customer)) return json(res, 403, { error: "Not allowed." });
    const { email, days, note } = JSON.parse((await readBody(req)).toString() || "{}");
    if (!email) return json(res, 400, { error: "An email is required." });
    const licence = issue(db, { email, days: days || null, note });
    await send({
      to: email,
      subject: "Your Jendela. licence",
      text: `Here is your licence key:\n\n${licence.key}\n`,
    });
    json(res, 200, { ok: true, key: licence.key });
  },

  "POST /api/admin/licence/revoke": async (req, res) => {
    const customer = currentCustomer(req);
    if (!isAdmin(customer)) return json(res, 403, { error: "Not allowed." });
    const { id } = JSON.parse((await readBody(req)).toString() || "{}");
    json(res, 200, { ok: revoke(db, id) });
  },

  "GET /api/admin/whoami": (req, res) => {
    const customer = currentCustomer(req);
    json(res, 200, { admin: isAdmin(customer), email: customer?.email ?? null });
  },

  /// Counted, then redirected. Nothing about who is downloading is stored.
  "GET /download": (req, res) => {
    let manifest = {};
    try {
      manifest = JSON.parse(fs.readFileSync(path.join(WEB_ROOT, "appcast.json"), "utf8"));
    } catch {
      return json(res, 503, { error: "No build published yet." });
    }
    record(db, "download", manifest.version);
    res.writeHead(302, { location: manifest.url });
    res.end();
  },
};

/// Static files, searched across the site, the dashboard and shared assets.
function serveStatic(req, res, url) {
  let name = url.pathname === "/" ? "/index.html" : url.pathname;
  // /admin and /admin/ both mean the dashboard's index.
  if (name === "/admin" || name === "/admin/") name = "/index.html";
  const clean = path.normalize(name).replace(/^(\.\.[/\\])+/, "");

  let file = null;
  for (const root of ROOTS) {
    const candidate = path.join(root, clean);
    if (candidate.startsWith(path.resolve(root)) && fs.existsSync(candidate)
        && fs.statSync(candidate).isFile()) {
      file = candidate;
      break;
    }
  }
  if (!file) {
    res.writeHead(404, { "content-type": "text/plain" });
    return res.end("Not found");
  }
  const types = {
    ".html": "text/html", ".css": "text/css", ".js": "text/javascript",
    ".json": "application/json", ".png": "image/png", ".svg": "image/svg+xml",
  };
  res.writeHead(200, { "content-type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
}

export const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, SITE);
  const route = routes[`${req.method} ${url.pathname}`];
  try {
    if (route) return await route(req, res, url);
    if (req.method === "GET") return serveStatic(req, res, url);
    json(res, 404, { error: "Not found." });
  } catch (error) {
    console.error(error);
    json(res, 500, { error: "Something went wrong." });
  }
});

if (process.argv[1]?.endsWith("server.mjs")) {
  server.listen(PORT, () => console.log(`Jendela. server on ${SITE}`));
}
export { db };
