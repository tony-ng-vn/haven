// The waitlist confirmation email. Split in two on purpose: renderConfirmation
// is a pure function (name in, {subject, html, text} out) so the templating and
// HTML-escaping are unit-testable without any network, and sendWaitlistConfirmation
// is the thin, env-gated transport. fetch is available in the default Convex
// runtime, so this file needs no "use node".

// The name is untrusted (anyone can submit any string) and lands inside HTML.
// Escape the five characters that would otherwise break out of text content or
// an attribute, so a crafted name can never inject markup into the message.
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export type Confirmation = {
  subject: string;
  html: string;
  text: string;
};

// One template, two renderings that must say the same thing. The plain-text
// part is what non-HTML clients (and spam filters) read, so it is not optional.
export function renderConfirmation(name: string): Confirmation {
  const safeName = escapeHtml(name);
  const subject = "You're on the Euno waitlist";

  const text = [
    `Hi ${name},`,
    "",
    "You're on the list.",
    "",
    "Euno's mission is to bring everyone together as we move through life. We have a strong belief that while new people are fascinating, it becomes less important to meet them if we eventually forget who they are and lose them along the way. With Euno, we will prevent that, and every connection will become a part of your life.",
    "",
    "Thank you for joining us on this journey. We're looking forward to having you with us.",
    "",
    "- Tony (Euno's founder)",
  ].join("\n");

  const html = `<!doctype html>
<html lang="en">
  <body style="margin:0;padding:0;background:#05070f;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#05070f;">
      <tr>
        <td align="center" style="padding:48px 24px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
            <tr>
              <td style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#f5f7fb;">
                <p style="margin:0 0 24px;font-size:13px;letter-spacing:0.08em;text-transform:uppercase;color:#7c8496;">Euno &middot; private beta</p>
                <h1 style="margin:0 0 16px;font-size:24px;line-height:1.3;font-weight:600;color:#ffffff;">Hi ${safeName}, you're on the list.</h1>
                <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#c7cdda;">Euno's mission is to bring everyone together as we move through life. We have a strong belief that while new people are fascinating, it becomes less important to meet them if we eventually forget who they are and lose them along the way. With Euno, we will prevent that, and every connection will become a part of your life.</p>
                <p style="margin:0 0 16px;font-size:16px;line-height:1.6;color:#c7cdda;">Thank you for joining us on this journey. We're looking forward to having you with us.</p>
                <p style="margin:32px 0 0;font-size:14px;color:#7c8496;">- Tony (Euno's founder)</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;

  return { subject, html, text };
}

export type SendResult =
  | { status: "sent"; id: string }
  | { status: "skipped"; reason: string }
  | { status: "failed"; error: string };

// Provider-agnostic entry point. Today it posts to Resend; the whole HTTP shape
// lives here so swapping providers touches this one function. Both credentials
// are read from the Convex deployment env (like OPENAI_API_KEY): when either is
// unset it returns "skipped" rather than throwing, which is the safe no-op that
// lets the join flow ship before an email provider is wired up.
export async function sendWaitlistConfirmation(args: {
  to: string;
  name: string;
}): Promise<SendResult> {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.WAITLIST_FROM_EMAIL;
  // The only falsy values process.env can hold are undefined and "" -- both
  // mean "not configured", so this is the safe no-op gate.
  if (!apiKey || !from) {
    return {
      status: "skipped",
      reason: "RESEND_API_KEY or WAITLIST_FROM_EMAIL is not set on the deployment",
    };
  }

  const { subject, html, text } = renderConfirmation(args.name);
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ from, to: args.to, subject, html, text }),
  });

  if (!response.ok) {
    return {
      status: "failed",
      error: `Resend responded ${response.status}: ${await response.text()}`,
    };
  }

  const data = (await response.json()) as { id?: string };
  return { status: "sent", id: data.id ?? "" };
}
