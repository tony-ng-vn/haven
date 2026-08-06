// "Same person?" while typing a name into SearchAdd's add form.
//
// The web mirror of ios/Haven/Shared/NameSuggestion.swift -- same fold (this
// file imports convex/nameSearch.ts's normalizeName rather than re-deriving
// it, which is also what powers search_normalized_name and personHandles, so
// "close" here means the same thing search already means), same edit
// distance, same length-scaled thresholds. Picking one of these arms
// attachToPersonId on the save, which is what lets a user answer "same
// person?" affirmatively instead of minting a twin.

import { normalizeName } from "../convex/nameSearch";

/// Classic Levenshtein, not Damerau-Levenshtein: a transposed pair of letters
/// costs two substitutions here rather than one swap. Deliberate, not a
/// simplification left half-finished -- nameSuggestions's threshold for a
/// name long enough to carry a transposition is already two, so the case
/// this exists for ("Duogn" for "Duong") is caught either way, and the
/// simpler algorithm is the one with nothing extra to get wrong.
// Unicode code points, not UTF-16 code units: an astral-plane character (a
// rare surname glyph, some emoji) is one grapheme's worth of "did they typo
// this" but two UTF-16 units, and indexing raw strings would count it twice
// -- both here and in the length check nameSuggestions does before ever
// calling this. Array.from splits on code points; converted once per string,
// not per cell, so the DP still runs in the same O(len(a) * len(b)).
export function levenshtein(a: string, b: string): number {
  const av = Array.from(a);
  const bv = Array.from(b);
  if (av.length === 0) return bv.length;
  if (bv.length === 0) return av.length;
  // Two rows rather than a full matrix: only the previous row is ever read
  // while filling the current one.
  let previous = Array.from({ length: bv.length + 1 }, (_, j) => j);
  let current = new Array<number>(bv.length + 1).fill(0);
  for (let i = 1; i <= av.length; i++) {
    current[0] = i;
    for (let j = 1; j <= bv.length; j++) {
      const cost = av[i - 1] === bv[j - 1] ? 0 : 1;
      current[j] = Math.min(
        previous[j] + 1, // deletion
        current[j - 1] + 1, // insertion
        previous[j - 1] + cost, // substitution
      );
    }
    [previous, current] = [current, previous];
  }
  return previous[bv.length];
}

/// Below this folded length, only an exact match counts.
///
/// A short name is not a safer edit-distance bet, it is a more dangerous
/// one: at two or three letters, a distance of one or two reaches nearly
/// every other short name, and "close match" stops meaning anything. This is
/// the line "Dun Duogn" surfacing "Dun Duong" is allowed to cross and "Al"
/// surfacing "Ali" is not.
const MINIMUM_FUZZY_LENGTH = 4;

/// How many edits still count as "the same name, mistyped," scaled by how
/// much of the name there is to go wrong: a longer name has more room for one
/// wrong letter to still be recognizable, and a name below
/// MINIMUM_FUZZY_LENGTH gets no fuzzy allowance at all.
function distanceLimit(foldedLength: number): number {
  if (foldedLength < MINIMUM_FUZZY_LENGTH) return 0;
  if (foldedLength < 8) return 1;
  return 2;
}

export type NameMatchKind = "exact" | "close";

export type NameSuggestion<T> = { item: T; kind: NameMatchKind };

/// Who a typed name might already be: exact matches first, then close ones --
/// small typos, caught by edit distance over the same fold normalizeName uses
/// everywhere else a name is compared.
///
/// Distance-checked names have to be within `limit` of each other in length
/// before the full comparison runs at all: Levenshtein distance is never
/// smaller than the length difference between two strings, so a pair already
/// too far apart on length cannot pass regardless, and skipping them is an
/// early exit rather than a separate rule.
///
/// candidates is whatever pool the caller already has in hand -- SearchAdd
/// passes the live name-search results, not a full directory scan, so a
/// person the server's own search index does not surface for this query
/// cannot be suggested here either, however close the edit distance.
export function nameSuggestions<T>(
  query: string,
  candidates: T[],
  nameOf: (candidate: T) => string,
  limit = 5,
): NameSuggestion<T>[] {
  const folded = normalizeName(query);
  if (folded === "") return [];
  // Counted once here, not per candidate comparison: distanceLimit and the
  // length-diff early exit both want code points, and re-splitting the same
  // query string on every candidate in the pool would be wasted work for a
  // number that never changes mid-loop.
  const foldedLength = Array.from(folded).length;
  const limitForFolded = distanceLimit(foldedLength);

  const exact: NameSuggestion<T>[] = [];
  const close: NameSuggestion<T>[] = [];
  for (const candidate of candidates) {
    const candidateFolded = normalizeName(nameOf(candidate));
    if (candidateFolded === "") continue;
    if (candidateFolded === folded) {
      exact.push({ item: candidate, kind: "exact" });
      continue;
    }
    if (limitForFolded <= 0) {
      continue;
    }
    const candidateLength = Array.from(candidateFolded).length;
    if (Math.abs(candidateLength - foldedLength) > limitForFolded) {
      continue;
    }
    if (levenshtein(folded, candidateFolded) <= limitForFolded) {
      close.push({ item: candidate, kind: "close" });
    }
  }
  return [...exact, ...close].slice(0, limit);
}
