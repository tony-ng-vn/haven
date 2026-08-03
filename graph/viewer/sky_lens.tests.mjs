/* Tests for sky_lens.mjs -- plain `node sky_lens.tests.mjs`, zero dependencies
 * (node:test and node:assert are Node builtins). See build.py's header comment for why
 * this file's import is guaranteed to be the exact code template-sky.html ships.
 *
 * Every fixture below is hand-rolled and entirely invented: fake ids, no real data of
 * any kind.
 */
"use strict";

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import { computeLens, computeLensMesh, formatPersonLabel, resolvePersonLabel, normalizeEditsPayload } from "./sky_lens.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));

const NODE_IDS = ["user", "ana", "bo", "cass", "dev"];
const EDGES = [
  { a: "user", b: "ana", reason: "oneToOneThread", strength: 12 },
  { a: "bo", b: "g1", reason: "groupMembership", strength: 3 },
  { a: "user", b: "g1", reason: "userGroupMembership", strength: 3 }
];
const ACQUAINTANCES = [
  { a: "ana", b: "bo", tier: "strong", score: 1.1, evidence: [] },
  { a: "bo", b: "cass", tier: "likely", score: 0.3, evidence: [] },
  { a: "dev", b: "bo", tier: "confirmed", score: 2.0, evidence: [] }
];

test("computeLens returns one entry per acquaintance pair naming the focused person, tier passed through", () => {
  const result = computeLens("bo", ACQUAINTANCES, EDGES, [], NODE_IDS);
  const byNeighbor = Object.fromEntries(result.map(r => [r.neighborId, r.tier]));
  assert.deepEqual(byNeighbor, { ana: "strong", cass: "likely", dev: "confirmed" });
});

test("computeLens matches the pair regardless of whether the focused person is a or b", () => {
  // "ana" is acq.a in the ana/bo pair, and acq.b in nothing here -- flip roles to confirm both sides work.
  const acq = [{ a: "cass", b: "ana", tier: "strong", score: 1, evidence: [] }];
  const result = computeLens("ana", acq, [], [], NODE_IDS);
  assert.deepEqual(result, [{ neighborId: "cass", tier: "strong", directToYou: false, interactionCount: 0 }]);
});

test("computeLens marks directToYou true only for a neighbor with a real one-to-one thread to user", () => {
  const result = computeLens("bo", ACQUAINTANCES, EDGES, [], NODE_IDS);
  const byNeighbor = Object.fromEntries(result.map(r => [r.neighborId, r.directToYou]));
  // ana has a oneToOneThread to user; cass and dev do not.
  assert.deepEqual(byNeighbor, { ana: true, cass: false, dev: false });
});

test("computeLens does not treat a group-membership edge to user as directToYou", () => {
  // bo's only edge to "user machinery" is via the group g1 (userGroupMembership), never a real thread.
  const result = computeLens("cass", [{ a: "bo", b: "cass", tier: "likely", score: 0.3, evidence: [] }], EDGES, [], NODE_IDS);
  assert.deepEqual(result, [{ neighborId: "bo", tier: "likely", directToYou: false, interactionCount: 0 }]);
});

test("computeLens excludes a neighbor listed in deletedIds", () => {
  const result = computeLens("bo", ACQUAINTANCES, EDGES, ["ana"], NODE_IDS);
  assert.deepEqual(result.map(r => r.neighborId).sort(), ["cass", "dev"]);
});

test("computeLens excludes a neighbor id not present in nodeIds", () => {
  const nodeIdsWithoutCass = NODE_IDS.filter(id => id !== "cass");
  const result = computeLens("bo", ACQUAINTANCES, EDGES, [], nodeIdsWithoutCass);
  assert.deepEqual(result.map(r => r.neighborId).sort(), ["ana", "dev"]);
});

test("computeLens returns [] when acquaintances is missing (an export that predates the field)", () => {
  assert.deepEqual(computeLens("bo", undefined, EDGES, [], NODE_IDS), []);
  assert.deepEqual(computeLens("bo", null, EDGES, [], NODE_IDS), []);
  assert.deepEqual(computeLens("bo", [], EDGES, [], NODE_IDS), []);
});

test("computeLens returns [] when the focus is the user", () => {
  assert.deepEqual(computeLens("user", ACQUAINTANCES, EDGES, [], NODE_IDS), []);
});

test("computeLens returns [] for an unknown or empty focus id", () => {
  assert.deepEqual(computeLens("nobody", ACQUAINTANCES, EDGES, [], NODE_IDS), []);
  assert.deepEqual(computeLens(null, ACQUAINTANCES, EDGES, [], NODE_IDS), []);
  assert.deepEqual(computeLens("", ACQUAINTANCES, EDGES, [], NODE_IDS), []);
});

test("computeLens ignores an acquaintance pair that does not involve the focused person", () => {
  const result = computeLens("dev", [{ a: "ana", b: "bo", tier: "strong", score: 1, evidence: [] }], EDGES, [], NODE_IDS);
  assert.deepEqual(result, []);
});

test("computeLens accepts a Set for deletedIds/nodeIds as well as an array", () => {
  const result = computeLens("bo", ACQUAINTANCES, EDGES, new Set(["ana"]), new Set(NODE_IDS));
  assert.deepEqual(result.map(r => r.neighborId).sort(), ["cass", "dev"]);
});

test("computeLensMesh returns a pair for two neighbors who also know each other, tier passed through", () => {
  // dev/bo is in ACQUAINTANCES but bo is the lensed person here, not a neighbor -- only
  // ana/bo's neighbor-to-neighbor counterpart matters: neither ana nor cass/dev pairs
  // exist above, so build a dedicated fixture naming two neighbors directly.
  const acq = [
    { a: "ana", b: "bo", tier: "strong", score: 1, evidence: [] },   // focus(dev)-neighbor, ignored here
    { a: "ana", b: "cass", tier: "likely", score: 0.3, evidence: [] } // neighbor-to-neighbor
  ];
  const result = computeLensMesh(["ana", "cass"], acq);
  assert.deepEqual(result, [{ a: "ana", b: "cass", tier: "likely", interactionCount: 0 }]);
});

test("computeLensMesh excludes a pair where only one end is a lens neighbor", () => {
  const acq = [{ a: "ana", b: "someoneElse", tier: "strong", score: 1, evidence: [] }];
  assert.deepEqual(computeLensMesh(["ana", "cass"], acq), []);
});

test("computeLensMesh returns [] with fewer than two neighbor ids", () => {
  assert.deepEqual(computeLensMesh(["ana"], ACQUAINTANCES), []);
  assert.deepEqual(computeLensMesh([], ACQUAINTANCES), []);
});

test("computeLensMesh returns [] when acquaintances is missing", () => {
  assert.deepEqual(computeLensMesh(["ana", "cass"], undefined), []);
  assert.deepEqual(computeLensMesh(["ana", "cass"], null), []);
  assert.deepEqual(computeLensMesh(["ana", "cass"], []), []);
});

test("computeLensMesh dedupes a pair that appears more than once", () => {
  const acq = [
    { a: "ana", b: "cass", tier: "likely", score: 0.3, evidence: [] },
    { a: "cass", b: "ana", tier: "likely", score: 0.3, evidence: [] } // same pair, flipped, defensive only
  ];
  assert.equal(computeLensMesh(["ana", "cass"], acq).length, 1);
});

test("computeLensMesh accepts a Set for neighborIds", () => {
  const acq = [{ a: "ana", b: "cass", tier: "strong", score: 1, evidence: [] }];
  assert.deepEqual(computeLensMesh(new Set(["ana", "cass"]), acq), [{ a: "ana", b: "cass", tier: "strong", interactionCount: 0 }]);
});

/* ============================================================
   interactionCount passthrough (tapback/reply evidence, GraphCore's
   AcquaintanceScoring.interactionPromotionThreshold) -- both computeLens and
   computeLensMesh must pass the export's per-pair interactionCount through untouched, and
   fall back to 0 for an export produced before the field existed.
   ============================================================ */

test("computeLens passes interactionCount through for a pair that carries it", () => {
  const acq = [{ a: "bo", b: "dev", tier: "strong", score: 1, evidence: [], interactionCount: 5 }];
  const result = computeLens("bo", acq, EDGES, [], NODE_IDS);
  assert.deepEqual(result, [{ neighborId: "dev", tier: "strong", directToYou: false, interactionCount: 5 }]);
});

test("computeLens defaults interactionCount to 0 for an export that predates the field", () => {
  // No `interactionCount` key at all on the acquaintance entry -- exactly what an export built
  // before this feature shipped looks like.
  const acq = [{ a: "bo", b: "dev", tier: "strong", score: 1, evidence: [] }];
  const result = computeLens("bo", acq, EDGES, [], NODE_IDS);
  assert.deepEqual(result, [{ neighborId: "dev", tier: "strong", directToYou: false, interactionCount: 0 }]);
});

test("computeLensMesh passes interactionCount through for a pair that carries it", () => {
  const acq = [{ a: "ana", b: "cass", tier: "likely", score: 0.3, evidence: [], interactionCount: 7 }];
  const result = computeLensMesh(["ana", "cass"], acq);
  assert.deepEqual(result, [{ a: "ana", b: "cass", tier: "likely", interactionCount: 7 }]);
});

test("computeLensMesh defaults interactionCount to 0 for an export that predates the field", () => {
  const acq = [{ a: "ana", b: "cass", tier: "likely", score: 0.3, evidence: [] }];
  const result = computeLensMesh(["ana", "cass"], acq);
  assert.deepEqual(result, [{ a: "ana", b: "cass", tier: "likely", interactionCount: 0 }]);
});

/* ============================================================
   formatPersonLabel (name-disambiguator label formatting, GraphJSON's `disambiguator`
   field): a person's name plus an optional quieter suffix distinguishing them from
   another exported node sharing the exact same display name.
   ============================================================ */

test("formatPersonLabel returns the suffix untouched when a disambiguator is present", () => {
  assert.deepEqual(formatPersonLabel("Jon Ashwick", "...9821"), { name: "Jon Ashwick", suffix: "...9821" });
});

test("formatPersonLabel returns a null suffix when disambiguator is absent (an export that predates the field)", () => {
  assert.deepEqual(formatPersonLabel("Jon Ashwick", undefined), { name: "Jon Ashwick", suffix: null });
});

test("formatPersonLabel returns a null suffix for an explicit null disambiguator", () => {
  assert.deepEqual(formatPersonLabel("Jon Ashwick", null), { name: "Jon Ashwick", suffix: null });
});

test("formatPersonLabel returns a null suffix for an empty-string disambiguator, never an empty badge", () => {
  assert.deepEqual(formatPersonLabel("Jon Ashwick", ""), { name: "Jon Ashwick", suffix: null });
});

test("formatPersonLabel never returns the literal string \"undefined\" for any missing-field shape", () => {
  for (const missing of [undefined, null, "", 0, false]) {
    const result = formatPersonLabel("Jon Ashwick", missing);
    assert.notEqual(result.suffix, "undefined");
    assert.equal(result.suffix, null);
  }
});

test("formatPersonLabel passes the name through unchanged, including a nullish name", () => {
  assert.equal(formatPersonLabel("Ana Vray", "...1234").name, "Ana Vray");
  assert.equal(formatPersonLabel(null, "...1234").name, null);
});

/* ============================================================
   resolvePersonLabel: the sky's one label-resolution rule now that a person can carry a
   custom (user-typed) name on top of a real contact name or a model guess. Priority is
   custom > real > guess > raw id fallback. Pure -- no DOM, no EDITS, no localStorage; the
   caller looks up whatever customName string (or none) applies and passes it in.
   ============================================================ */

test("resolvePersonLabel: a custom name wins over a real (contact-card) name", () => {
  const result = resolvePersonLabel("Real Name", "Custom Name", "+15550001111");
  assert.deepEqual(result, { name: "Custom Name", labelKind: "custom" });
});

test("resolvePersonLabel: a custom name wins over a guess-derived tilde name", () => {
  const result = resolvePersonLabel("~Guessed Name", "Custom Name", "+15550001111");
  assert.deepEqual(result, { name: "Custom Name", labelKind: "custom" });
});

test("resolvePersonLabel: no custom name falls back to today's rule -- real name wins over a guess", () => {
  assert.deepEqual(resolvePersonLabel("Real Name", null, "+15550001111"), { name: "Real Name", labelKind: "name" });
  assert.deepEqual(resolvePersonLabel("Real Name", undefined, "+15550001111"), { name: "Real Name", labelKind: "name" });
});

test("resolvePersonLabel: no custom name and no real name falls back to the guess, tilde stripped", () => {
  assert.deepEqual(resolvePersonLabel("~Guessed Name", "", "+15550001111"), { name: "Guessed Name", labelKind: "guess" });
});

test("resolvePersonLabel: no custom name, no real name, no guess falls back to the raw id", () => {
  assert.deepEqual(resolvePersonLabel(null, null, "+15550001111"), { name: "+15550001111", labelKind: "phone" });
});

test("resolvePersonLabel: a whitespace-only custom name is treated as no custom name (clears, does not save blank)", () => {
  assert.deepEqual(resolvePersonLabel("Real Name", "   ", "+15550001111"), { name: "Real Name", labelKind: "name" });
});

test("resolvePersonLabel: a custom name is trimmed", () => {
  assert.deepEqual(resolvePersonLabel("Real Name", "  Custom Name  ", "+15550001111"), { name: "Custom Name", labelKind: "custom" });
});

test("resolvePersonLabel: a custom name that collides with another displayed name still renders its disambiguator -- formatPersonLabel does not care where the name came from", () => {
  const resolved = resolvePersonLabel("Real Name", "Custom Name", "+15550001111");
  const labeled = formatPersonLabel(resolved.name, "...1111");
  assert.deepEqual(labeled, { name: "Custom Name", suffix: "...1111" });
});

/* ============================================================
   normalizeEditsPayload: the pure heart of loadEdits -- given whatever JSON.parse
   handed back (or null, for "nothing stored"), returns a safe { v, moves, deleted, names }
   shape. localStorage/JSON.parse/try-catch stay in template-sky.html; this function is
   what "unknown shape -> start clean" and the v1-plus-names back-compat migration mean.
   ============================================================ */

test("normalizeEditsPayload: nothing stored (null) returns a clean empty shape", () => {
  assert.deepEqual(normalizeEditsPayload(null), { v: 1, moves: {}, deleted: [], names: {} });
});

test("normalizeEditsPayload: an unknown shape (wrong version) starts clean rather than misreading it", () => {
  assert.deepEqual(normalizeEditsPayload({ v: 2, moves: { x: 1 }, deleted: ["x"], names: { x: "X" } }),
    { v: 1, moves: {}, deleted: [], names: {} });
  assert.deepEqual(normalizeEditsPayload({ notEvenTheRightShape: true }), { v: 1, moves: {}, deleted: [], names: {} });
});

test("normalizeEditsPayload: a v1 payload from before renaming existed (no `names` key) loads fine and keeps moves/deleted", () => {
  const oldPayload = { v: 1, moves: { "+15550001111": 2 }, deleted: ["+15559998888"] };
  assert.deepEqual(normalizeEditsPayload(oldPayload), {
    v: 1,
    moves: { "+15550001111": 2 },
    deleted: ["+15559998888"],
    names: {}
  });
});

test("normalizeEditsPayload: a full v1 payload with names round-trips unchanged", () => {
  const payload = { v: 1, moves: { a: 1 }, deleted: ["b"], names: { c: "Custom Name" } };
  assert.deepEqual(normalizeEditsPayload(payload), payload);
});

test("normalizeEditsPayload: malformed moves/deleted/names fields fall back to empty individually", () => {
  assert.deepEqual(
    normalizeEditsPayload({ v: 1, moves: "not an object", deleted: "not an array", names: 42 }),
    { v: 1, moves: {}, deleted: [], names: {} }
  );
});

/* ============================================================
   Production-integration guard: the real template must declare the viewer-core
   placeholder EXACTLY ONCE (this file's own module is what fills it) and the graph
   JSON placeholder exactly once, or build.py / SkyExportBuilder both fail loudly at
   build time -- see build.py's header comment for the shared contract. Asserted here,
   not just exercised by hand, so a stray second mention of either placeholder (e.g.
   written out in a doc comment) is caught by `node sky_lens.tests.mjs` too.
   ============================================================ */
test("template-sky.html declares the graph-json and viewer-core placeholders exactly once each", () => {
  const template = readFileSync(path.join(HERE, "template-sky.html"), "utf8");
  const countOf = needle => template.split(needle).length - 1;
  assert.equal(countOf("__GRAPH_JSON__"), 1, "__GRAPH_JSON__ must appear exactly once");
  assert.equal(countOf("__VIEWER_CORE_JS__"), 1, "__VIEWER_CORE_JS__ must appear exactly once");
});
