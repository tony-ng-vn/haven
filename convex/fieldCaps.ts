// How long a free-text card field may be, and the one check that enforces it.
// Plain helpers, not registered Convex functions -- profiles.ts and people.ts
// both need these, and one definition is what keeps your own card and a
// person you saved from disagreeing about what fits.
//
// The product capped these on the client and the server did not: the
// onboarding prototype has held name at 40 since the design was ratified,
// while updateMyProfile, addPerson and editPerson accepted a megabyte. A cap
// only the client enforces is not a cap -- the iOS fields have none today,
// and every one of these values is rendered on a card sized for a line.

const NAME_MAX = 40;
// The prototype's number, and the card's name line is drawn for it.
export const CARD_NAME_MAX = NAME_MAX;
// A city as the completer returns it ("Ho Chi Minh City", "Newcastle upon
// Tyne") plus room for a typed one. Its admin area and country ride along and
// are rendered beside it, so they get the same budget.
export const CITY_PART_MAX = 40;
// Company and role are edit-only fields the card renders as one line each,
// the same budget as a handle. The prototype never had a field for either,
// so there is no ratified number to match -- this is the rendering
// constraint, written down.
export const CARD_LINE_MAX = 60;
// The prototype's handle field. Long enough for the longest LinkedIn slug
// and an international phone number with spaces.
export const HANDLE_MAX = 60;

// Counted in code points, not UTF-16 units: the cap exists so a value fits a
// line, and one emoji or one composed Vietnamese vowel is one thing on that
// line rather than two.
export function tooLong(value: string, max: number): boolean {
  return Array.from(value).length > max;
}

// Throws with the field named, because every caller of this is an
// interactive edit where the person can shorten what they typed. A path that
// cannot ask -- a queued capture replayed by the drain long after the sheet
// closed -- must truncate instead, never throw.
export function requireWithin(label: string, value: string, max: number): void {
  if (tooLong(value, max)) {
    throw new Error(`Keep ${label} under ${max} characters`);
  }
}
