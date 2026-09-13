import { DatabaseSync } from "node:sqlite";
import crypto from "node:crypto";

/// SQLite, built into Node — no dependency to audit, no service to run, and the
/// whole database is one file to back up.
export function open(path = process.env.DB_PATH || "./jendela.db") {
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA journal_mode = WAL;

    CREATE TABLE IF NOT EXISTS customers (
      id         TEXT PRIMARY KEY,
      email      TEXT NOT NULL UNIQUE,
      created_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS licences (
      id          TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL REFERENCES customers(id),
      key         TEXT NOT NULL,
      kind        TEXT NOT NULL,            -- lifetime | subscription
      status      TEXT NOT NULL,            -- active | refunded | revoked
      order_ref   TEXT,                     -- provider order id, for reconciliation
      amount      INTEGER,                  -- minor units, as charged
      currency    TEXT,
      created_at  INTEGER NOT NULL,
      revoked_at  INTEGER
    );
    CREATE INDEX IF NOT EXISTS licences_customer ON licences(customer_id);
    CREATE UNIQUE INDEX IF NOT EXISTS licences_order ON licences(order_ref) WHERE order_ref IS NOT NULL;

    CREATE TABLE IF NOT EXISTS sessions (
      token      TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL REFERENCES customers(id),
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS login_tokens (
      token      TEXT PRIMARY KEY,
      email      TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      used_at    INTEGER
    );

    -- First-party analytics: counts, not people. No IP, no user agent, no
    -- identifiers, so the privacy claim on the site stays true.
    CREATE TABLE IF NOT EXISTS events (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      kind    TEXT NOT NULL,               -- download | activation | purchase | refund
      version TEXT,
      day     TEXT NOT NULL,               -- YYYY-MM-DD
      at      INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS events_day ON events(day, kind);
  `);
  return db;
}

export const now = () => Math.floor(Date.now() / 1000);
export const today = () => new Date().toISOString().slice(0, 10);
export const token = () => crypto.randomBytes(32).toString("base64url");

export function customerByEmail(db, email) {
  const clean = String(email).trim().toLowerCase();
  const found = db.prepare("SELECT * FROM customers WHERE email = ?").get(clean);
  if (found) return found;
  const row = { id: crypto.randomUUID(), email: clean, created_at: now() };
  db.prepare("INSERT INTO customers (id, email, created_at) VALUES (?, ?, ?)")
    .run(row.id, row.email, row.created_at);
  return row;
}

export function record(db, kind, version = null) {
  db.prepare("INSERT INTO events (kind, version, day, at) VALUES (?, ?, ?, ?)")
    .run(kind, version, today(), now());
}
