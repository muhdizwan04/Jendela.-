import crypto from "node:crypto";
import { now, today, record } from "./db.mjs";
import { mint } from "./licence.mjs";

/// Admin is a single address, named in the environment, signing in through the
/// same magic link as everyone else. That avoids a second password to protect
/// and a second auth path to get wrong — there is only one way in, and it is
/// the one that is already tested.
export function isAdmin(customer) {
  const allowed = (process.env.ADMIN_EMAIL || "").trim().toLowerCase();
  return Boolean(allowed) && customer?.email === allowed;
}

const days = (count) => {
  const out = [];
  for (let i = count - 1; i >= 0; i--) {
    out.push(new Date(Date.now() - i * 86400000).toISOString().slice(0, 10));
  }
  return out;
};

export function stats(db) {
  const window = days(14);
  const from = window[0];

  const perDay = (kind) => {
    const rows = db
      .prepare("SELECT day, COUNT(*) AS n FROM events WHERE kind = ? AND day >= ? GROUP BY day")
      .all(kind, from);
    const map = Object.fromEntries(rows.map((r) => [r.day, r.n]));
    return window.map((day) => ({ day, count: map[day] || 0 }));
  };

  const money = db
    .prepare("SELECT COALESCE(SUM(amount),0) AS total, currency FROM licences WHERE status = 'active' GROUP BY currency")
    .all();

  return {
    generatedAt: now(),
    totals: {
      customers: db.prepare("SELECT COUNT(*) AS n FROM customers").get().n,
      active: db.prepare("SELECT COUNT(*) AS n FROM licences WHERE status = 'active'").get().n,
      refunded: db.prepare("SELECT COUNT(*) AS n FROM licences WHERE status = 'refunded'").get().n,
      revoked: db.prepare("SELECT COUNT(*) AS n FROM licences WHERE status = 'revoked'").get().n,
      downloads: db.prepare("SELECT COUNT(*) AS n FROM events WHERE kind = 'download'").get().n,
    },
    revenue: money,
    downloads: perDay("download"),
    purchases: perDay("purchase"),
    versions: db
      .prepare("SELECT version, COUNT(*) AS n FROM events WHERE kind = 'download' AND version IS NOT NULL GROUP BY version ORDER BY n DESC")
      .all(),
    recent: db
      .prepare(`SELECT l.created_at, l.kind, l.status, l.amount, l.currency, c.email
                FROM licences l JOIN customers c ON c.id = l.customer_id
                ORDER BY l.created_at DESC LIMIT 12`)
      .all(),
  };
}

export function search(db, query) {
  const like = `%${String(query || "").trim().toLowerCase()}%`;
  return db
    .prepare(`SELECT c.id, c.email, c.created_at,
                     (SELECT COUNT(*) FROM licences WHERE customer_id = c.id AND status = 'active') AS active
              FROM customers c WHERE c.email LIKE ? ORDER BY c.created_at DESC LIMIT 25`)
    .all(like)
    .map((customer) => ({
      ...customer,
      licences: db
        .prepare("SELECT id, key, kind, status, amount, currency, created_at FROM licences WHERE customer_id = ? ORDER BY created_at DESC")
        .all(customer.id),
    }));
}

/// Issuing by hand: support cases, replacements, review copies.
export function issue(db, { email, days: validFor = null, note = null }) {
  const clean = String(email).trim().toLowerCase();
  let customer = db.prepare("SELECT * FROM customers WHERE email = ?").get(clean);
  if (!customer) {
    customer = { id: crypto.randomUUID(), email: clean, created_at: now() };
    db.prepare("INSERT INTO customers (id, email, created_at) VALUES (?, ?, ?)")
      .run(customer.id, customer.email, customer.created_at);
  }
  const licence = mint({ email: clean, days: validFor });
  db.prepare(
    `INSERT INTO licences (id, customer_id, key, kind, status, order_ref, amount, currency, created_at)
     VALUES (?, ?, ?, ?, 'active', ?, 0, NULL, ?)`
  ).run(
    licence.id, customer.id, licence.key,
    validFor ? "subscription" : "lifetime",
    note ? `manual:${note}` : `manual:${licence.id}`,
    now()
  );
  record(db, "purchase");
  return licence;
}

/// Revoking marks the row, but cannot reach a key already on someone's Mac:
/// licences verify offline, which is the whole point. Only a licence with an
/// expiry stops working by itself.
export function revoke(db, licenceId) {
  const result = db
    .prepare("UPDATE licences SET status = 'revoked', revoked_at = ? WHERE id = ? AND status != 'revoked'")
    .run(now(), licenceId);
  return result.changes > 0;
}
