// Plain helper, not a registered Convex function -- importing it from
// people.ts needs no _generated/api.d.ts patch.
//
// The user's own network is mostly Vietnamese, so search has to be
// accent-insensitive: "dun" must find a person stored as "Dun Dun" whether
// they typed the D-stroke (U+0110/U+0111), diacritics (base letter plus
// combining marks), or both.

// Unicode NFD decomposes most Latin diacritics into a base letter plus
// combining marks (which we then strip), but the Vietnamese D-stroke is not
// a base letter + diacritic under Unicode -- it is its own codepoint that
// NFD cannot split. Map it explicitly via \u escapes (keeps this file
// plain ASCII) before decomposing everything else.
const D_STROKE_UPPER = "\u0110"; // Latin capital letter D with stroke
const D_STROKE_LOWER = "\u0111"; // Latin small letter d with stroke

export function normalizeName(name: string): string {
  return name
    .replace(new RegExp(D_STROKE_UPPER, "g"), "D")
    .replace(new RegExp(D_STROKE_LOWER, "g"), "d")
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

// One normalized haystack for the keyword side of the MVP search contract:
// everything the owner can read on the card, folded exactly the way the
// query will be. The contract only promises keywords-over-notes; indexing
// the rest of the card is a strict superset that keeps one search box
// honest ("dung" finds the person whether it was in the note or the name).
// Every code path that inserts or edits a people row must write this field,
// or the row goes invisible to keyword search (see backfillSearchText).
export function personSearchText(person: {
  name: string;
  headline?: string;
  bio?: string;
  company?: string;
  role?: string;
  city?: { name: string };
  handle?: string;
  contactHandles?: Array<{ value: string }>;
  context?: string;
}): string {
  return normalizeName(
    [
      person.name,
      person.headline,
      person.bio,
      person.company,
      person.role,
      person.city?.name,
      person.handle,
      ...(person.contactHandles ?? []).map((handle) => handle.value),
      person.context,
    ]
      .filter(
        (part): part is string => part !== undefined && part.trim() !== "",
      )
      .join(" "),
  );
}
