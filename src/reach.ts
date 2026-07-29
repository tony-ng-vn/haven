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
// nine characters that encodeURIComponent escapes. Putting them back is what
// makes a handle saved on a phone and the same handle opened from the web
// resolve to the same address, character for character.
const KEPT_BY_URL_PATH_ALLOWED = /%(24|26|2B|2C|2F|3A|3B|3D|40)/g;

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
    return `https://${address}${escapeForPath(trimmed)}`;
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
/// A number is kept as typed. iOS folds one to E.164 with libphonenumber, which
/// takes that whole library to do honestly, and reading a number back is
/// already handled where it matters, in reachUrl.
export function reachValue(platform: string, raw: string): string {
  let value = raw.trim();
  const entry = known(platform);
  if (entry === undefined || isPhoneNumber(platform)) return value;

  // Each address is looked for in the whole string before anything is cut, so
  // a platform with a second one still finds it. Cutting first would leave
  // "https:" and match neither.
  const lowered = value.toLowerCase();
  for (const address of entry.addresses) {
    const at = lowered.indexOf(address);
    if (at === -1) continue;
    value = value.slice(at + address.length);
    break;
  }
  // Everything up to the first separator: a second path segment, a query or a
  // fragment on a profile link is nobody's handle.
  value = value.split(/[/?#]/)[0];
  return value.replace(/^@+/, "").replace(/@+$/, "");
}
