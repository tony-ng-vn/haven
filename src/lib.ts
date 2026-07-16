// Small pure helpers shared by the screens. Kept free of React and Convex
// imports so they stay trivially unit-testable.

export type AuthFlow = "signIn" | "signUp";

// Convex Auth surfaces provider failures as opaque server error strings, so
// matching substrings is the only stable-enough signal we have. Wrong email
// and wrong password map to one message on purpose: no account enumeration.
export function mapAuthError(error: unknown, flow: AuthFlow): string {
  const raw = error instanceof Error ? error.message : String(error ?? "");
  const message = raw.toLowerCase();

  if (message.includes("failed to fetch") || message.includes("network")) {
    return "Could not reach the server. Check your connection and try again.";
  }
  if (flow === "signUp" && message.includes("already exists")) {
    return "An account with that email already exists. Try signing in instead.";
  }
  if (message.includes("invalid password")) {
    return "Passwords need at least 8 characters.";
  }
  if (
    message.includes("invalidaccountid") ||
    message.includes("invalidsecret")
  ) {
    return "That email and password do not match.";
  }
  return "Something went wrong. Please try again.";
}

// People paste links loosely ("linkedin.com/in/..."). Return an openable
// http(s) URL, or null when the text is not a link at all.
export function normalizeUrl(raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed === "" || /\s/.test(trimmed)) {
    return null;
  }
  if (/^https?:\/\//i.test(trimmed)) {
    return trimmed;
  }
  // Any other explicit scheme (ftp:, mailto:, javascript:) is not openable
  // from here; only bare domains get upgraded.
  if (/^[a-z][a-z0-9+.-]*:/i.test(trimmed)) {
    return null;
  }
  if (!trimmed.includes(".")) {
    return null;
  }
  return `https://${trimmed}`;
}

// "June 2026" -- the quiet memory anchor under a person's name.
export function formatMonthYear(ms: number, locale?: string): string {
  return new Intl.DateTimeFormat(locale, {
    month: "long",
    year: "numeric",
  }).format(new Date(ms));
}
