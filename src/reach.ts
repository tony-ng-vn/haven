// Where a saved person's handle actually goes.
//
// The web mirror of ios/Haven/Directory/PersonReach.swift. Reach is the fourth
// stroke of the loop -- Capture, Refine, Recall, Reach -- and the only one that
// leaves Haven. A handle Haven cannot open is still worth showing: it is how
// you reach them, whether or not the reaching happens from here.
//
// A lookup with an honest miss rather than a closed union, because a saved
// person's platforms are free-form on purpose: your own card offers four, and
// somebody you wrote down can carry any handle you wanted to record.

type Known = {
  label: string;
  /// The addresses this platform serves a profile from. The first is the one
  /// Haven links to; the rest are older names the same profile still answers
  /// to, which matter when somebody pastes one in. Empty for a platform whose
  /// value is a number rather than part of a web address.
  addresses: string[];
};

// The platforms Haven knows how to open. twitter is here as well as x because
// rows written before the rename still say twitter, and the person behind them
// has not moved.
const KNOWN = new Map<string, Known>([
  ["instagram", { label: "Instagram", addresses: ["instagram.com/"] }],
  ["x", { label: "X", addresses: ["x.com/", "twitter.com/"] }],
  ["twitter", { label: "X", addresses: ["x.com/", "twitter.com/"] }],
  ["linkedin", { label: "LinkedIn", addresses: ["linkedin.com/in/"] }],
  ["telegram", { label: "Telegram", addresses: ["t.me/", "telegram.me/"] }],
  ["whatsapp", { label: "WhatsApp", addresses: [] }],
  ["phone", { label: "Phone", addresses: [] }],
]);

/// The platforms the handle editor offers.
///
/// Longer than the four your own card offers, and that asymmetry is the spec's:
/// your card is an identity you publish, this is a note about how you actually
/// reach one person, WhatsApp and Telegram included. twitter is readable but not
/// offerable -- it is the old name for a platform that has one.
///
/// Offering a list rather than a free text box is a decision about dedup, not
/// about capability: the server takes any string, and one person typing
/// "WhatsApp" while another types "whats app" makes two identities for one
/// platform, invisibly.
export const REACH_PLATFORMS = [
  "instagram",
  "x",
  "linkedin",
  "phone",
  "whatsapp",
  "telegram",
] as const;

function normalize(platform: string): string {
  return platform.trim().toLowerCase();
}

/// Whether two stored platform strings name the same platform.
///
/// Exported because a raw `===` is wrong on data the server takes verbatim: a
/// row can hold "Instagram" while `preferredPlatform` says "instagram", and
/// comparing the two literally would quietly fail to mark the row somebody
/// chose. Every other platform read here already folds first.
export function samePlatform(a: string, b: string | undefined): boolean {
  return b !== undefined && normalize(a) === normalize(b);
}

function known(platform: string): Known | undefined {
  return KNOWN.get(normalize(platform));
}

/// What the platform is called out loud.
///
/// An unknown platform is read back as it was written rather than dressed up:
/// somebody who typed "signal" gets "signal", which is true, and Haven does not
/// pretend to know a platform it does not.
export function reachLabel(platform: string): string {
  return known(platform)?.label ?? platform;
}

/// Whether this handle is a phone number, which decides the keyboard the field
/// asks for and whether an at-sign belongs in front of it.
export function isPhoneNumber(platform: string): boolean {
  const name = normalize(platform);
  return name === "phone" || name === "whatsapp";
}

export function reachPlaceholder(platform: string): string {
  return isPhoneNumber(platform)
    ? "Their number"
    : "Paste a link or type the handle";
}

/// `[0-9]` as JavaScript means it, which is what the iOS side spells
/// `isASCIIDigit` so a number is read the same on both.
function digitsOnly(value: string): string {
  return value.replace(/[^0-9]/g, "");
}

/// The digits of a number, keeping a leading plus.
function dialable(value: string): string {
  const digits = digitsOnly(value);
  if (digits === "") return "";
  return value.startsWith("+") ? `+${digits}` : digits;
}

// Swift escapes a handle with CharacterSet.urlPathAllowed, which keeps these
// eight characters that encodeURIComponent escapes. Putting them back is what
// makes a handle saved on a phone and the same handle opened from the web
// resolve to the same address, character for character.
//
// Verified by running both sides over printable ASCII rather than read off a
// table: a colon is escaped by BOTH and must not be listed here. This pins
// another platform's runtime behaviour, and it was checked against Foundation
// 26 only -- ios/project.yml still targets iOS 17, whose older encoding table
// may differ. PersonReachTests carries the matching case on the Swift side.
const KEPT_BY_URL_PATH_ALLOWED = /%(24|26|2B|2C|2F|3B|3D|40)/g;

function escapeForPath(value: string): string {
  return encodeURIComponent(value).replace(
    KEPT_BY_URL_PATH_ALLOWED,
    (_, hex: string) => String.fromCharCode(parseInt(hex, 16)),
  );
}

/// What to open when somebody taps this handle, or null when there is nothing to
/// open.
///
/// Null is an ordinary answer. A handle on a platform Haven has never heard of
/// is a real way to reach somebody and the row still shows it; it just does not
/// promise a tap it cannot keep.
export function reachUrl(platform: string, value: string): string | null {
  const trimmed = value.trim();
  const entry = known(platform);
  if (trimmed === "" || entry === undefined) return null;

  const [address] = entry.addresses;
  if (address !== undefined) {
    // encodeURIComponent throws on a lone surrogate. Convex cannot store one,
    // so this is only reachable from a value built in the browser -- but this
    // function promises a url or null, and a throw from inside render is
    // neither.
    try {
      return `https://${address}${escapeForPath(trimmed)}`;
    } catch {
      return null;
    }
  }

  // The two platforms with no address hold a number instead of a handle.
  if (normalize(platform) === "phone") {
    // A number is dialled, not browsed. Everything but the digits and a
    // leading plus goes: a stored "+84 90 123 4567" is one number, and tel:
    // does not want its spaces.
    const number = dialable(trimmed);
    return number === "" ? null : `tel:${number}`;
  }
  // wa.me addresses a number without its plus.
  const digits = digitsOnly(trimmed);
  return digits === "" ? null : `https://wa.me/${digits}`;
}

/// What to store for a handle somebody typed or pasted.
///
/// The field asks them to paste a link, because pasting the profile link is the
/// normal thing to do with a profile -- so the handle is dug out of it rather
/// than demanded on its own, the same folding
/// ios/Haven/Onboarding/ContactValue.swift does behind the contact question.
/// Without it a stored "https://instagram.com/mai.makes" reads back as
/// instagram.com/https://instagram.com/mai.makes, which is the dead link this
/// whole file exists to stop.
///
/// What is not mirrored is that file's other half, each platform's character
/// and length rules: there they exist to keep Continue disabled, and here there
/// is nothing to disable -- the server caps the length, and Haven does not know
/// a platform's naming rules better than the person writing the handle down.
///
/// Null means "that is not a handle I can read", which is an answer, not a
/// failure: iOS's parse returns nil for the same inputs and saves nothing.
/// Returning wreckage instead would be worse than refusing, because this value
/// is an identity key -- handleValueKey trims, strips @ and lowercases it, so
/// every unreadable paste for one platform would collapse onto the SAME key and
/// two unrelated people would collide in personHandles.
///
/// A number is kept as typed. iOS folds one to E.164 with libphonenumber, which
/// takes that whole library to do honestly. Reading a number back is handled in
/// reachUrl, but the two platforms do still disagree on the stored string, so a
/// person saved on both makes two keys rather than one. That is a real gap and
/// closing it needs a phone library here, not a regex.
export function reachValue(platform: string, raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed === "") return null;
  const entry = known(platform);
  if (entry === undefined || isPhoneNumber(platform)) return trimmed;

  // Whether this reads as a web address at all. A handle cannot hold a colon or
  // a slash, and a bare host is an address somebody stopped typing.
  const looksLikeAddress =
    /[:/]/.test(trimmed) ||
    entry.addresses.some((address) => {
      const host = address.split("/")[0];
      return startsWithFolded(trimmed, host) || startsWithFolded(trimmed, `www.${host}`);
    });

  // Searched in the whole string before anything is cut, so a platform with a
  // second address still finds it. Indexed on the original rather than a
  // lowercased copy: toLowerCase can change a string's length, and the two
  // would then disagree about where the handle starts.
  let value = trimmed;
  const cut = foldPastAddress(trimmed, entry.addresses);
  if (cut !== null) {
    value = cut;
  } else if (looksLikeAddress) {
    // An address on this platform that Haven does not recognize the shape of --
    // linkedin.com/pub/..., a /mwlite/ share link. There is no handle in here
    // that Haven can name, so it says so.
    return null;
  }

  // Everything up to the first separator: a second path segment, a query or a
  // fragment on a profile link is nobody's handle.
  value = value.split(/[/?#]/)[0].replace(/^@+/, "").replace(/@+$/, "");
  // Whatever survived has to be a handle now. Anything still carrying address
  // punctuation means the fold did not reach the end of the address -- a link
  // pasted into a link does this -- and a handle is not what is left.
  if (value === "" || /[:/?#\s]/.test(value)) return null;
  return value;
}

function startsWithFolded(value: string, prefix: string): boolean {
  return value.slice(0, prefix.length).toLowerCase() === prefix.toLowerCase();
}

/// What follows the first of these addresses in the string, or null if none of
/// them is in it.
function foldPastAddress(value: string, addresses: string[]): string | null {
  for (const address of addresses) {
    const at = value.toLowerCase().indexOf(address);
    // Guard the one case where the lowercased copy cannot be indexed back into
    // the original: a fold that changes length (U+0130 becomes two characters).
    if (at === -1 || value.toLowerCase().length !== value.length) continue;
    return value.slice(at + address.length);
  }
  return null;
}
