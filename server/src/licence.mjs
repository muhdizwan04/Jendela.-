import crypto from "node:crypto";

/// Signs licence keys in the same format the app verifies.
///
/// The private key lives only in the environment. The app ships the matching
/// public key and nothing else, so a leak of the app cannot mint licences —
/// but a leak of this key can mint every licence ever, which is why it is never
/// written to the database, the logs, or a file in the repository.
const PKCS8_ED25519_PREFIX = Buffer.from("302e020100300506032b657004220420", "hex");

function privateKey() {
  const raw = process.env.LICENCE_PRIVATE_KEY;
  if (!raw) throw new Error("LICENCE_PRIVATE_KEY is not set");
  const seed = Buffer.from(raw.trim(), "base64");
  if (seed.length !== 32) throw new Error("LICENCE_PRIVATE_KEY must be a 32-byte base64 seed");
  return crypto.createPrivateKey({
    key: Buffer.concat([PKCS8_ED25519_PREFIX, seed]),
    format: "der",
    type: "pkcs8",
  });
}

const base64url = (buffer) =>
  buffer.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/** Mints a licence. `days` omitted means a lifetime licence. */
export function mint({ email, id = crypto.randomUUID(), days = null }) {
  const payload = {
    email,
    id,
    issued: Math.floor(Date.now() / 1000),
    product: "jendela",
    ...(days ? { expires: Math.floor(Date.now() / 1000) + days * 86400 } : {}),
  };
  const body = Buffer.from(JSON.stringify(payload));
  const signature = crypto.sign(null, body, privateKey());
  return { key: `JNDL1.${base64url(body)}.${base64url(signature)}`, id, payload };
}

/** Present so tests can prove a tampered key fails without involving the app. */
export function verify(key) {
  const parts = String(key).split(".");
  if (parts.length !== 3 || parts[0] !== "JNDL1") return null;
  const pad = (s) => s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4);
  const body = Buffer.from(pad(parts[1]), "base64");
  const signature = Buffer.from(pad(parts[2]), "base64");

  const seed = Buffer.from(process.env.LICENCE_PRIVATE_KEY.trim(), "base64");
  const pub = crypto.createPublicKey({
    key: Buffer.concat([PKCS8_ED25519_PREFIX, seed]),
    format: "der",
    type: "pkcs8",
  });
  if (!crypto.verify(null, body, pub, signature)) return null;
  try {
    return JSON.parse(body.toString());
  } catch {
    return null;
  }
}
