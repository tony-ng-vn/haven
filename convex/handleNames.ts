// What a handle may be, and which ones the site keeps for itself.
//
// Handles live at the root of the site: a card is inhavens.com/<handle>, with
// no prefix above it. That makes every handle a competitor for a top-level
// path, so the words the site needs for itself have to be held back before
// somebody claims one and the page it names becomes unreachable.
//
// Deliberately free of Convex imports, the same way handleKeys is: the web app
// routes with this list and the backend claims against it, and two copies would
// drift the day one of them gained a word.

// The shape of a claimable handle. One definition because both ends read it:
// the backend rejects a claim that fails it, and the web router uses it to tell
// a card url from some other path. Two copies would drift the day one changed,
// and the failure that follows is quiet -- a real card that stops resolving.
export const HANDLE_PATTERN = /^[a-z0-9_]{3,24}$/;

// Only names a handle could actually take are worth listing. USERNAME_PATTERN
// is /^[a-z0-9_]{3,24}$/, so anything carrying a dot or a hyphen -- og.png,
// sign-in, apple-app-site-association -- is already unclaimable and does not
// belong here.
const RESERVED = new Set<string>([
  // Pages the law and the App Store ask for. Review rule 5.1.1 blocks
  // submission without the first two.
  "privacy",
  "terms",
  "legal",
  "security",
  "support",
  "help",
  "contact",
  "about",

  // Routes the app already answers, or will.
  "signin",
  "signup",
  "login",
  "logout",
  "join",
  "waitlist",
  "preview",
  "festival",
  "landing",
  // Your Sky's own download page, at inhavens.com/sky -- same shadowing risk
  // as "landing" and "waitlist" just above: a card claimed here would make
  // that page permanently unreachable.
  "sky",
  "home",
  "search",
  "people",
  "card",
  "beacon",
  "settings",
  "account",
  "profile",
  "auth",
  "callback",

  // The brand, so nobody can pose as it.
  "haven",
  "havens",
  "inhaven",
  "inhavens",

  // Infrastructure names, held back because a card sitting on one of these is
  // confusing at best and a phishing surface at worst.
  "www",
  "api",
  "app",
  "admin",
  "root",
  "static",
  "assets",
  "public",
  "cdn",
  "mail",
  "blog",
  "docs",
  "status",
  "health",
]);

/// Whether this name belongs to the site rather than to a person.
export function isReservedHandle(handle: string): boolean {
  return RESERVED.has(handle.trim().toLowerCase());
}

/// Whether a person could hold this name: well formed, and not the site's.
export function isClaimableHandle(handle: string): boolean {
  return HANDLE_PATTERN.test(handle) && !isReservedHandle(handle);
}
