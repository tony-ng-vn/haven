// Mirrors ios/HavenTests/NameSuggestionTests.swift fixture for fixture: same
// fold, same edit distance, same length-scaled thresholds, so a case that
// reads as close on one client reads as close on the other.

import { describe, expect, test } from "vitest";
import { levenshtein, nameSuggestions } from "./nameSuggestion";

type Candidate = { id: string; name: string };

function candidate(id: string, name: string): Candidate {
  return { id, name };
}

describe("Levenshtein distance", () => {
  test("identical strings are zero apart", () => {
    expect(levenshtein("mai", "mai")).toBe(0);
    expect(levenshtein("", "")).toBe(0);
  });

  test("one substitution is distance one", () => {
    expect(levenshtein("mai", "mae")).toBe(1);
  });

  test("one insertion or deletion is distance one", () => {
    expect(levenshtein("mai", "mail")).toBe(1);
    expect(levenshtein("mail", "mai")).toBe(1);
  });

  // The brief's own example: a transposed pair of letters at the end. Plain
  // Levenshtein (no transposition move) counts this as two substitutions,
  // not one swap -- exactly why the suggester's threshold for a name this
  // long is two, not one.
  test("a transposed pair costs two under plain Levenshtein", () => {
    expect(levenshtein("duogn", "duong")).toBe(2);
  });

  test("an empty string against another is the other's length", () => {
    expect(levenshtein("", "mai")).toBe(3);
    expect(levenshtein("mai", "")).toBe(3);
  });

  test("completely different strings are far apart", () => {
    expect(levenshtein("mai tran", "ada lovelace")).toBeGreaterThan(5);
  });
});

describe("suggesting who a typed name might already be", () => {
  test("a name that folds identically is an exact suggestion", () => {
    const suggestions = nameSuggestions(
      "mai tran",
      [candidate("p1", "Mai Tran")],
      (c) => c.name,
    );
    expect(suggestions.map((s) => s.item.id)).toEqual(["p1"]);
    expect(suggestions[0]?.kind).toBe("exact");
  });

  // Diacritics fold away before anything else happens, so this is exact, not
  // close -- the fold, not the distance check, is what answers it.
  test("accents and case do not turn an exact match into a close one", () => {
    const suggestions = nameSuggestions(
      "nguyen mai",
      [candidate("p1", "Nguy\u1EC5n Mai")],
      (c) => c.name,
    );
    expect(suggestions[0]?.kind).toBe("exact");
  });

  // The brief's flagship case: a two-letter typo at the end of a long enough
  // name still surfaces the person it means.
  test("Dun Duogn surfaces Dun Duong as a close match", () => {
    const suggestions = nameSuggestions(
      "Dun Duogn",
      [candidate("p1", "Dun Duong")],
      (c) => c.name,
    );
    expect(suggestions.map((s) => s.item.id)).toEqual(["p1"]);
    expect(suggestions[0]?.kind).toBe("close");
  });

  // A diacritic fold and a genuine typo stacked on top of each other: the
  // fold has to run before the distance check sees either name, or the
  // Vietnamese accent itself would be counted as part of the typo.
  test("a typo on top of a diacritic still surfaces as close, not unrelated", () => {
    const suggestions = nameSuggestions(
      "Nguyen Mail",
      [candidate("p1", "Nguy\u1EC5n Mai")],
      (c) => c.name,
    );
    expect(suggestions.map((s) => s.item.id)).toEqual(["p1"]);
    expect(suggestions[0]?.kind).toBe("close");
  });

  // A hyphen dropped in favor of a space is a plausible, real typo, and the
  // fold leaves hyphens alone -- the distance check is what has to catch
  // this one, not the fold.
  test("a hyphen typed as a space is a close match on a hyphenated name", () => {
    const suggestions = nameSuggestions(
      "Anne Marie Tran",
      [candidate("p1", "Anne-Marie Tran")],
      (c) => c.name,
    );
    expect(suggestions.map((s) => s.item.id)).toEqual(["p1"]);
    expect(suggestions[0]?.kind).toBe("close");
  });

  test("an exact hyphenated match is exact, not close", () => {
    const suggestions = nameSuggestions(
      "anne-marie tran",
      [candidate("p1", "Anne-Marie Tran")],
      (c) => c.name,
    );
    expect(suggestions[0]?.kind).toBe("exact");
  });

  test("unrelated names stay quiet", () => {
    const suggestions = nameSuggestions(
      "Mai Tran",
      [candidate("p1", "Ada Lovelace")],
      (c) => c.name,
    );
    expect(suggestions).toEqual([]);
  });

  // The short-name guard: a two- or three-letter query is exact-only, no
  // matter how close a longer or differently spelled name might read to a
  // person -- fuzzy-matching at that length would surface nearly everyone.
  test("a two-letter name never fuzzy-matches, even one edit away", () => {
    const suggestions = nameSuggestions(
      "Al",
      [candidate("p1", "Ali")],
      (c) => c.name,
    );
    expect(suggestions).toEqual([]);
  });

  test("a three-letter name still does not fuzzy-match", () => {
    const suggestions = nameSuggestions(
      "Mai",
      [candidate("p1", "Mae")],
      (c) => c.name,
    );
    expect(suggestions).toEqual([]);
  });

  // One letter longer than the guard: now a single-edit typo is allowed
  // through, which is the boundary the guard is drawn at.
  test("a four-letter name allows a single-edit typo", () => {
    const suggestions = nameSuggestions(
      "Maya",
      [candidate("p1", "Mayo")],
      (c) => c.name,
    );
    expect(suggestions.map((s) => s.item.id)).toEqual(["p1"]);
    expect(suggestions[0]?.kind).toBe("close");
  });

  test("exact matches are listed ahead of close matches", () => {
    const suggestions = nameSuggestions(
      "Dun Duogn",
      [candidate("close", "Dun Duong"), candidate("exact", "Dun Duogn")],
      (c) => c.name,
    );
    expect(suggestions.map((s) => s.item.id)).toEqual(["exact", "close"]);
  });

  test("a blank query suggests nobody", () => {
    const suggestions = nameSuggestions(
      "   ",
      [candidate("p1", "Mai Tran")],
      (c) => c.name,
    );
    expect(suggestions).toEqual([]);
  });

  // Astral-plane characters (outside the BMP) take two UTF-16 code units
  // each but are one Unicode code point. A length check done in UTF-16 units
  // over-counts a name carrying one of these -- three code points reads as
  // four -- and can wrongly let the fuzzy-match guard through on a name that
  // should still be exact-only.
  test("an astral-plane character does not inflate the short-name guard", () => {
    const suggestions = nameSuggestions(
      "\u{20BB7}\u7530\u4E2D",
      [candidate("p1", "\u{20BB7}\u7530\u4EF2")],
      (c) => c.name,
    );
    expect(suggestions).toEqual([]);
  });

  test("results are capped at the given limit, exact first", () => {
    const suggestions = nameSuggestions(
      "Maya",
      [candidate("p1", "Mayo"), candidate("p2", "Maga"), candidate("p3", "Mays")],
      (c) => c.name,
      2,
    );
    expect(suggestions).toHaveLength(2);
  });
});
