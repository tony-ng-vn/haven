// Small pure helpers shared by the screens. Kept free of React and runtime
// Convex imports so they stay trivially unit-testable.

import type { Doc } from "../convex/_generated/dataModel";

// What the detail screen needs to render instantly from data the search
// results already hold, before its own query answers.
export type PersonSnapshot = Pick<
  Doc<"people">,
  "_id" | "name" | "link" | "context" | "_creationTime"
>;

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

// Waitlist join. One normalized form so "Tony@Example.com " and
// "tony@example.com" collapse to the same row when we dedupe.
export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

// Haven's admin allowlist. Baked in as a default so admin-only surfaces work
// in any deployment without extra env wiring; VITE_ADMIN_EMAILS can extend it
// (comma-separated) without a code change. All comparisons go through
// normalizeEmail, so case and stray whitespace never matter.
export const DEFAULT_ADMIN_EMAILS = ["tonythiennguyen17@gmail.com"];

// Merge the baked-in admins with any from VITE_ADMIN_EMAILS into one
// deduped, normalized list. Kept pure (env value passed in) so it is
// trivially testable and never touches import.meta at call time.
export function parseAdminEmails(raw: string | undefined): string[] {
  const fromEnv = (raw ?? "")
    .split(",")
    .map(normalizeEmail)
    .filter((email) => email !== "");
  return [
    ...new Set([...DEFAULT_ADMIN_EMAILS.map(normalizeEmail), ...fromEnv]),
  ];
}

// Whether a signed-in identity's email is on the admin allowlist. A missing
// email (null/undefined) is never an admin.
export function isAdminEmail(
  email: string | null | undefined,
  admins: string[],
): boolean {
  if (email === null || email === undefined) return false;
  return admins.includes(normalizeEmail(email));
}

// A deliberately conservative shape check: exactly one @, non-empty local and
// domain, a dot in the domain, no whitespace, within RFC 5321's 254-char
// ceiling. Real deliverability is proven by the invite, not by a regex.
export function isValidEmail(raw: string): boolean {
  const email = raw.trim();
  if (email.length === 0 || email.length > 254) return false;
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

// The public waitlist lives at "#/join" (a trailing slash is tolerated). Kept
// separate from isClerkFlowHash so this route reads as a public page, not an
// auth callback to hand to Clerk.
export function isJoinHash(hash: string): boolean {
  return /^#\/join\/?$/.test(hash);
}

// "June 2026" -- the quiet memory anchor under a person's name.
export function formatMonthYear(ms: number, locale?: string): string {
  return new Intl.DateTimeFormat(locale, {
    month: "long",
    year: "numeric",
  }).format(new Date(ms));
}

// Platforms whose profile URL is just the visible handle. LinkedIn and
// Facebook use slugs that never appear in a profile screenshot, so they
// cannot be derived -- the user pastes those links instead.
const HANDLE_URLS: Record<string, (handle: string) => string> = {
  x: (h) => `https://x.com/${h}`,
  instagram: (h) => `https://instagram.com/${h}`,
  github: (h) => `https://github.com/${h}`,
  tiktok: (h) => `https://www.tiktok.com/@${h}`,
  threads: (h) => `https://www.threads.net/@${h}`,
  bluesky: (h) => `https://bsky.app/profile/${h}`,
};

export function deriveProfileUrl(
  platform: string,
  handle: string | undefined,
): string | null {
  const build = HANDLE_URLS[platform];
  if (build === undefined || handle === undefined) {
    return null;
  }
  const cleaned = handle.trim().replace(/^@/, "");
  if (cleaned === "") {
    return null;
  }
  // A mangled handle ("ada l", "a/b") must not break the URL or add a path
  // segment -- encode it before it reaches the template.
  return build(encodeURIComponent(cleaned));
}

// The text a person's embedding is computed from. Deterministic on purpose:
// the stored copy doubles as an idempotency key for re-embedding.
export function buildEmbedText(fields: {
  name: string;
  platform?: string;
  handle?: string;
  headline?: string;
  context?: string;
}): string {
  const platformLine = [fields.platform, fields.handle]
    .filter((part) => part !== undefined && part.trim() !== "")
    .join(" ");
  return [fields.name, platformLine, fields.headline, fields.context]
    .filter((part): part is string => part !== undefined && part.trim() !== "")
    .join("\n");
}

// Manual triage: the human is the OCR. Join a first and last name into one
// display name -- trim both, collapse runs of inner whitespace, single space
// between. "" when nothing real was typed, which is also the can-save gate.
export function composeName(first: string, last: string): string {
  return `${first} ${last}`.replace(/\s+/g, " ").trim();
}

// The subtitle under a manually named star: workplace and school. Both ->
// "WORK -- SCHOOL", one -> that one, neither -> undefined (nothing to store).
export function composeHeadline(
  work: string,
  school: string,
): string | undefined {
  const w = work.trim();
  const s = school.trim();
  if (w !== "" && s !== "") return `${w} -- ${s}`;
  if (w !== "") return w;
  if (s !== "") return s;
  return undefined;
}

// A manual card can only leave the deck once it actually names someone.
export function canSaveManualName(name: string): boolean {
  return name.trim() !== "";
}

// The atlas home renders the recent field plus anything search surfaced that
// is not already in it. Matches MUST materialize as clusters: an off-field
// person who never renders is unreachable, and the "Add" affordance would
// then invite creating their duplicate. Recent people stay first so their
// spiral positions never shift; off-field name matches append next, then
// semantic-only matches.
export function composeAtlasField<T extends { _id: string }>(
  recent: T[],
  nameMatches: T[],
  semantic: T[],
): T[] {
  const seen = new Set(recent.map((p) => p._id));
  const field = [...recent];
  for (const group of [nameMatches, semantic]) {
    for (const person of group) {
      if (!seen.has(person._id)) {
        seen.add(person._id);
        field.push(person);
      }
    }
  }
  return field;
}

// Clerk drives OAuth and verification steps through hash sub-routes it appends
// to our page, e.g. "#/sso-callback" after Google returns. The bare landing
// has no hash route, so a non-empty one means we must mount Clerk immediately
// to finish the handshake rather than show the sign-in button again.
export function isClerkFlowHash(hash: string): boolean {
  return /^#\/.+/.test(hash);
}

// What to paint on the very first frame, before Clerk has loaded. The signed-out
// landing needs nothing from Clerk, so a first-time visitor sees it immediately;
// only a returning visitor (session hint) waits on a splash, and a Clerk flow
// callback outranks both so the OAuth/verification handshake is never dropped.
export type BootMode = "landing" | "splash" | "clerk-flow";

export function bootMode(input: {
  hash: string;
  hasSessionHint: boolean;
}): BootMode {
  if (isClerkFlowHash(input.hash)) return "clerk-flow";
  if (input.hasSessionHint) return "splash";
  return "landing";
}

// The single source of truth for which top-level screen App renders. The
// signed-out default is the public waitlist -- that is the shareable root URL.
// Existing users still reach sign-in: Clerk OAuth/verification callbacks and
// the explicit "#/sign-in" route mount it, and a returning visitor with a live
// session resolves straight to Home (via the splash) without ever seeing the
// waitlist. The "#/join" route stays public even though it matches the generic
// Clerk-flow shape.
export type View = "home" | "signin" | "splash" | "waitlist";

export function resolveView(input: {
  isAuthenticated: boolean;
  isLoading: boolean;
  hash: string;
  hasSessionHint: boolean;
}): View {
  if (input.isAuthenticated) return "home";
  if (!isJoinHash(input.hash) && isClerkFlowHash(input.hash)) return "signin";
  if (input.isLoading && bootMode(input) === "splash") return "splash";
  return "waitlist";
}

// The triage card's drag gesture: scroll-style momentum projection for
// "where would the card coast to if released now?".
export function project(velocity: number, decelerationRate = 0.998): number {
  return ((velocity / 1000) * decelerationRate) / (1 - decelerationRate);
}

// Progressive resistance past a boundary; real things slow before they stop.
export function rubberband(
  overshoot: number,
  dimension = 320,
  constant = 0.55,
): number {
  return (
    (overshoot * dimension * constant) /
    (dimension + constant * Math.abs(overshoot))
  );
}

// Mirrors convex/captures.ts listCaptures's `.take(50)`. Once the queue
// hits this cap the client cannot tell whether more are queued
// server-side, so the toolbar count must read as a floor, not a total.
export const CAPTURE_QUEUE_CAP = 50;

export function triageCountLabel(queueLength: number): string {
  if (queueLength >= CAPTURE_QUEUE_CAP) return `${CAPTURE_QUEUE_CAP}+ to review`;
  if (queueLength === 1) return "1 to review";
  return `${queueLength} to review`;
}

export type SwipeVelocitySample = { t: number; x: number };
export type SwipeDecision = "save" | "context" | "settle";

// Whether a released triage card commits left (save), right (add context),
// or springs back to center. Velocity is read from the last ~100ms of
// pointer samples, projected forward, and added to the current drag
// position -- so a fast flick can commit the card even from short of the
// positional threshold, the way a scroll view keeps going after a flick.
export function decideSwipe(
  dragX: number,
  samples: SwipeVelocitySample[],
): SwipeDecision {
  if (samples.length === 0) return "settle";
  const last = samples[samples.length - 1];
  const first = samples.find((s) => last.t - s.t <= 100) ?? samples[0];
  const velocity =
    last.t > first.t ? ((last.x - first.x) / (last.t - first.t)) * 1000 : 0;
  const projected = dragX + project(velocity);
  if (projected < -240) return "save";
  if (projected > 240) return "context";
  return "settle";
}
