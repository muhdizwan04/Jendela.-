/// Sending is deliberately pluggable and off by default.
///
/// With no provider configured the magic link is written to the console
/// instead, so the whole flow can be exercised locally without an account
/// anywhere. Nothing silently pretends to have sent an email.
export async function send({ to, subject, text }) {
  const key = process.env.RESEND_API_KEY;
  const from = process.env.MAIL_FROM;

  if (!key || !from) {
    console.log(`\n[mail: not configured, printing instead]\n  to: ${to}\n  ${subject}\n  ${text}\n`);
    return { delivered: false, reason: "no provider configured" };
  }

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({ from, to, subject, text }),
  });
  if (!response.ok) {
    return { delivered: false, reason: `provider returned ${response.status}` };
  }
  return { delivered: true };
}
