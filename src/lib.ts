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
