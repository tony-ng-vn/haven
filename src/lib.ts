// Small pure helpers shared by the screens. Kept free of React and runtime
// Convex imports so they stay trivially unit-testable.

import type { Doc } from "../convex/_generated/dataModel";
import { isClaimableHandle } from "../convex/handleNames";

// What the detail screen needs to render instantly from data the search
// results already hold, before its own query answers.
//
// The wide half is optional and it is load-bearing, not generosity. searchPeople
// returns whole projected rows, so a tap on the atlas hands the detail screen
// the photo, the city and the connection too -- this type was the only thing
// hiding them. It mattered because the name travels: the shared-element morph
// captures the band as it will be, and reading these off the slower getPerson
// meant they landed after the transition and shoved the settled name upward.
//
// Optional because two callers legitimately carry less: a manual add builds a
// snapshot from what it just typed, and the semantic search source is narrower.
type ProjectedFields = {
  // Resolved server-side, so it is not a field on the document.
  photoUrl?: string | null;
  connection?: { state: "connected" | "ended"; peerUsername: string } | null;
};

export type PersonSnapshot = Pick<
  Doc<"people">,
  "_id" | "name" | "link" | "context" | "_creationTime"
> &
  Partial<
    Pick<
      Doc<"people">,
      | "headline"
      | "bio"
      | "city"
      | "company"
      | "role"
      | "contactHandles"
      | "preferredPlatform"
    >
  > &
  ProjectedFields;

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

// The download landing for Your Sky lives at "#/sky" (a trailing slash is
// tolerated), same tolerance as isJoinHash. Public and unauthenticated, so it
// gets the same carve-out ahead of the generic Clerk-flow check below.
export function isSkyHash(hash: string): boolean {
  return /^#\/sky\/?$/.test(hash);
}

// The iOS product landing -- which carries the waitlist signup -- lives at
// "#/ios" (a trailing slash tolerated), same shape as isSkyHash. Public and
// unauthenticated, so it gets the same carve-out ahead of the generic
// Clerk-flow check below.
export function isIosHash(hash: string): boolean {
  return /^#\/ios\/?$/.test(hash);
}

// An unlinked, experimental second landing concept lives at "#/landing2" (a
// trailing slash tolerated), same shape as isSkyHash/isIosHash. Nothing on
// the site links to it -- reached only by typing the url -- so it needs the
// same carve-out ahead of the generic Clerk-flow check below, or it would
// read as an OAuth callback and bounce to sign-in.
export function isLanding2Hash(hash: string): boolean {
  return /^#\/landing2\/?$/.test(hash);
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

// Which platform a shared profile URL belongs to. Only the three the share
// extension activates on; everything else is not a person link.
export type SharedPlatform = "instagram" | "linkedin" | "x";

// First path segments that are product surfaces, not people. A share of a
// reel or a login page must never become a person.
const RESERVED_PATHS: Record<SharedPlatform, readonly string[]> = {
  instagram: [
    "p",
    "reel",
    "reels",
    "stories",
    "tv",
    "explore",
    "accounts",
    "direct",
    "about",
  ],
  // LinkedIn needs no list: the /in/ prefix below already excludes every
  // other surface.
  linkedin: [],
  x: [
    "home",
    "explore",
    "search",
    "i",
    "intent",
    "hashtag",
    "messages",
    "notifications",
    "settings",
    "compose",
    "share",
  ],
};

// A specific post under a handle is content someone shared, not the profile;
// deeper profile tabs (/tagged, /in/<slug>/details) still identify the person.
const CONTENT_SUBPATHS: Record<SharedPlatform, readonly string[]> = {
  instagram: ["p", "reel", "tv"],
  linkedin: [],
  x: ["status"],
};

// The registrable domains that serve profiles, not exact hosts: share sheets
// hand over whichever host the app is on, and LinkedIn gives non-US members a
// country-prefixed one (vn.linkedin.com) alongside the www./m./mobile.
// variants.
const PROFILE_HOSTS: Record<string, SharedPlatform> = {
  "instagram.com": "instagram",
  "linkedin.com": "linkedin",
  "x.com": "x",
  "twitter.com": "x",
};

function platformForHost(host: string): SharedPlatform | undefined {
  for (const [domain, platform] of Object.entries(PROFILE_HOSTS)) {
    // A suffix match on a dot boundary, so "instagram.com.evil.example" is
    // still a stranger's host.
    if (host === domain || host.endsWith(`.${domain}`)) {
      return platform;
    }
  }
  return undefined;
}

// Handles arrive percent-encoded in a URL path; a malformed escape is a
// broken link, not a person.
function decodeSegment(segment: string): string | null {
  try {
    return decodeURIComponent(segment);
  } catch {
    return null;
  }
}

// The share extension's whole parse step: a profile URL in, the platform and
// handle out, null for anything that is not one person's profile. Pure and
// offline by design -- the URL is a pointer, never fetched.
export function parseProfileUrl(
  raw: string,
): { platform: SharedPlatform; handle: string } | null {
  const normalized = normalizeUrl(raw);
  if (normalized === null) return null;
  let url: URL;
  try {
    url = new URL(normalized);
  } catch {
    return null;
  }
  const platform = platformForHost(url.hostname);
  if (platform === undefined) return null;

  const segments = url.pathname.split("/").filter((part) => part !== "");
  if (platform === "linkedin") {
    // The mobile-lite site serves the same profile one segment deeper.
    if (segments[0] === "mwlite") {
      segments.shift();
    }
    // Profiles live only under /in/<slug>; company, posts, pub and feed
    // paths are not a person we can identify.
    if (segments[0] !== "in") return null;
    segments.shift();
  }
  const handleSegment = segments[0];
  if (handleSegment === undefined) return null;
  const subSegment = segments[1];
  if (subSegment !== undefined) {
    // Decoded first, so "%73tatus" cannot smuggle a post past the check.
    const sub = decodeSegment(subSegment) ?? subSegment;
    if (CONTENT_SUBPATHS[platform].includes(sub.toLowerCase())) return null;
  }

  const decoded = decodeSegment(handleSegment);
  if (decoded === null) return null;
  // An encoded slash would otherwise fold a second path segment into the
  // handle, hiding the surface this URL actually points at.
  if (decoded.includes("/")) return null;
  const handle = decoded.replace(/^@+/, "");
  if (handle === "") return null;
  // Checked after decoding: "%70" is the reserved "p", and a post URL must
  // never become a person.
  if (RESERVED_PATHS[platform].includes(handle.toLowerCase())) return null;
  return { platform, handle };
}

// LinkedIn slugs carry the person's name plus a disambiguating id suffix
// ("mai-tran-8a91b2"). Guessing the name from it makes the share sheet's name
// field a confirmation rather than an empty box; "" when there is no guess.
export function nameGuessFromSlug(slug: string): string {
  const segments = slug.trim().split("-").filter((part) => part !== "");
  // Only the trailing id junk is dropped: digits earlier in a slug are part
  // of the handle someone actually chose.
  while (segments.length > 0 && /\d/.test(segments[segments.length - 1])) {
    segments.pop();
  }
  return segments
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

// The text a person's embedding is computed from. Deterministic on purpose:
// the stored copy doubles as an idempotency key for re-embedding.
export function buildEmbedText(fields: {
  name: string;
  platform?: string;
  handle?: string;
  headline?: string;
  bio?: string;
  role?: string;
  company?: string;
  cityName?: string;
  context?: string;
}): string {
  const platformLine = [fields.platform, fields.handle]
    .filter((part) => part !== undefined && part.trim() !== "")
    .join(" ");
  // "Compiler engineer at Analytical Engines" embeds as the phrase a memory
  // would use; either side alone still stands on its own.
  const role = fields.role?.trim() ?? "";
  const company = fields.company?.trim() ?? "";
  const workLine =
    role !== "" && company !== "" ? `${role} at ${company}` : role + company;
  return [
    fields.name,
    platformLine,
    fields.headline,
    fields.bio,
    workLine,
    fields.cityName,
    fields.context,
  ]
    .filter((part): part is string => part !== undefined && part.trim() !== "")
    .join("\n");
}

// One person as the model reads them in an ask. Deliberately terse: the whole
// network goes in one prompt, so every label costs tokens on every row.
//
// The ref, not the Convex id, is what the model answers with. Ids are ~32
// characters each and a model that mangles one produces a match pointing at
// nobody; a small integer is cheap to send and cheap to validate on the way
// back.
export function buildDossier(
  ref: number,
  person: {
    name: string;
    headline?: string;
    bio?: string;
    role?: string;
    company?: string;
    cityName?: string;
    platforms?: string[];
    memories?: Array<{ text: string; createdAt: number }>;
  },
): string {
  const role = person.role?.trim() ?? "";
  const company = person.company?.trim() ?? "";
  const workLine =
    role !== "" && company !== "" ? `${role} at ${company}` : role + company;
  const heading = [
    `#${ref} ${person.name}`,
    workLine,
    person.cityName,
    person.platforms?.join(", "),
  ]
    .filter((part): part is string => part !== undefined && part.trim() !== "")
    .join(" | ");
  const lines = [heading];
  if (person.headline !== undefined && person.headline.trim() !== "") {
    lines.push(person.headline);
  }
  if (person.bio !== undefined && person.bio.trim() !== "") {
    lines.push(person.bio);
  }
  for (const memory of person.memories ?? []) {
    // Dated because "who did I meet last month" is a memory query, and an
    // undated note cannot answer it.
    const day = new Date(memory.createdAt).toISOString().slice(0, 10);
    lines.push(`- ${day}: ${memory.text}`);
  }
  return lines.join("\n");
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

/// The paths that mean "let me in", or null when a path means something else.
///
/// Every word here is reserved in `handleNames`, so none can be somebody's
/// card. Reported from production: `/signin` and `/signup` both rendered the
/// waitlist, which tells a person who typed the most obvious url that Haven has
/// no sign-in at all.
///
/// Sub-paths count too, because Clerk owns them once its component is mounted
/// at one of these: `/sign-in/factor-one` is Clerk's second step, not a 404.
export function isAuthPath(pathname: string): boolean {
  const first = pathname.split("/").filter((segment) => segment !== "")[0];
  if (first === undefined) return false;
  return ["signin", "sign-in", "signup", "sign-up", "login"].includes(
    first.toLowerCase(),
  );
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
// signed-out default is the Haven landing -- that is the shareable root URL,
// telling people what Haven is and pointing them at the two products. Existing
// users still reach sign-in: Clerk OAuth/verification callbacks and the
// explicit "#/sign-in" route mount it, and a returning visitor with a live
// session resolves straight to Home (via the splash) without ever seeing the
// landing. The "#/join" route stays public even though it matches the generic
// Clerk-flow shape, and lands on "ios" -- the waitlist signup now lives on the
// iOS product page rather than at the root.
export type View =
  | "home"
  | "signin"
  | "splash"
  | "landing"
  | "landing-polished"
  | "card"
  | "legal"
  | "support"
  | "sky"
  | "ios"
  | "landing2";

/// The one path segment a url names, lowercased, or null when it names none or
/// more than one.
///
/// Every route the site owns lives at the top level, next to the cards, so they
/// all ask this same question first. A trailing slash and any casing are
/// forgiven, because a url typed or pasted by hand still has to land.
function topLevelSegment(pathname: string): string | null {
  const segments = pathname.split("/").filter((segment) => segment !== "");
  return segments.length === 1 ? segments[0].toLowerCase() : null;
}

/// The handle a path names, or null when the path is not somebody's card.
///
/// A card is inhavens.com/<handle> with nothing above it, so this doubles as
/// the guard that keeps the site's own paths out of the card route. It reads
/// the same rules the backend claims against, from the same module.
export function handleFromPath(pathname: string): string | null {
  const handle = topLevelSegment(pathname);
  if (handle === null) return null;
  return isClaimableHandle(handle) ? handle : null;
}

/// Which legal document a path names, or null when it names none.
export type LegalDoc = "privacy" | "terms";

/// Every page the site owns at its top level, handles included in the contest.
///
/// All three words are also held back in handleNames, so nobody can claim a
/// card at any of these paths -- but these routes are checked first regardless,
/// so the site keeps its own pages even if that list ever loses a word.
export type SitePage = LegalDoc | "support";

const SITE_PAGES: readonly SitePage[] = ["privacy", "terms", "support"];

export function sitePageFromPath(pathname: string): SitePage | null {
  const name = topLevelSegment(pathname);
  return SITE_PAGES.find((page) => page === name) ?? null;
}

/// The two documents the App Store asks for before it will take a submission.
///
/// Narrower than `sitePageFromPath` on purpose: this answers "which document
/// should LegalPage render", and support is a page but not a document.
export function legalDocFromPath(pathname: string): LegalDoc | null {
  const name = sitePageFromPath(pathname);
  return name === "privacy" || name === "terms" ? name : null;
}

/// Whether a path names the polished landing preview at inhavens.com/landing.
///
/// Kept standalone rather than folded into SitePage: that type's whole job is
/// "which page does LegalPage/SupportPage answer for", and widening it here
/// would blur that. Same trailing-slash and casing tolerance as
/// sitePageFromPath, via the same topLevelSegment helper -- and "landing" is
/// held back in handleNames the same way privacy/terms/support are, so no
/// card can ever shadow it.
export function isPolishedLandingPath(pathname: string): boolean {
  return topLevelSegment(pathname) === "landing";
}

export function resolveView(input: {
  isAuthenticated: boolean;
  isLoading: boolean;
  hash: string;
  hasSessionHint: boolean;
  pathname?: string;
}): View {
  // The site's own pages first, so no handle can ever shadow one. App Review
  // opens the privacy and support urls from App Store Connect, and anything
  // other than the page there reads as a broken link.
  //
  // Support is signed out for a reason beyond review: the most likely person
  // looking for help is one who cannot get into their account.
  const sitePage = sitePageFromPath(input.pathname ?? "/");
  if (sitePage === "support") return "support";
  if (sitePage !== null) return "legal";
  // The polished landing preview, same precedence as the site pages just
  // above and for the same reason: it has to be reachable by anyone with the
  // link, signed in or out, before the auth checks below ever run.
  if (isPolishedLandingPath(input.pathname ?? "/")) return "landing-polished";
  // Then cards, before the auth checks and deliberately so. The person this
  // page exists for is a stranger who just scanned a code, and they arrive
  // signed out: leaving it until after would sit them on a splash while Clerk
  // boots, and would send a signed-in visitor to their own home instead of the
  // card they opened.
  if (handleFromPath(input.pathname ?? "/") !== null) return "card";
  if (input.isAuthenticated) return "home";
  // Checked after the auth test, so somebody already signed in who lands on
  // /signin gets their people rather than a form asking them to do it again.
  if (isAuthPath(input.pathname ?? "/")) return "signin";
  // The Your Sky download page, public like "#/join" -- checked before the
  // generic Clerk-flow test below, which would otherwise treat "#/sky" as an
  // OAuth callback and route it to sign-in.
  if (isSkyHash(input.hash)) return "sky";
  // The iOS product page, public for the same reason -- and "#/join" is kept
  // as an alias into it, since it is where the waitlist signup lives now.
  if (isIosHash(input.hash) || isJoinHash(input.hash)) return "ios";
  // An unlinked second landing concept the owner is evaluating -- public and
  // unauthenticated like sky/ios above, reached only by typing the url.
  if (isLanding2Hash(input.hash)) return "landing2";
  if (isClerkFlowHash(input.hash)) return "signin";
  if (input.isLoading && bootMode(input) === "splash") return "splash";
  return "landing";
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
