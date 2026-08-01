/* Tests for viewer_core.mjs -- plain `node tests.mjs`, zero dependencies (node:test and node:assert are Node builtins).
 * See build.py's header comment for why this file's import is guaranteed to be the exact code template-v4.html ships.
 *
 * fixtures/synthetic.json is entirely invented: fake names, fake group chats, no real data of any kind.
 * Its exact shape (who is the bridge, who is the lurker, which chat is pre-listed in fullyAcquaintedChatIds, and so on) is documented in gen_fixture's role-assignment comments and re-derived here by id rather than by role name, since the ids are what the code actually sees. */
"use strict";

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import * as core from "./viewer_core.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_RAW = JSON.parse(readFileSync(path.join(HERE, "fixtures", "synthetic.json"), "utf8"));

// Deep-clone helper: several tests mutate a working copy (deleting keys to
// simulate an older export, or feeding malformed data) and must never touch
// the shared fixture object other tests read.
function cloneRaw() {
  return JSON.parse(JSON.stringify(FIXTURE_RAW));
}

// ids pulled from the fixture by structural role rather than hardcoded,
// so regenerating fixtures/synthetic.json with the same shape (same group
// roles, same group ids) does not require touching this file.
function findFixtureIds(raw) {
  const model = core.adaptRaw(raw);
  const ivy = model.groupById.get("g-ivy");
  const riverside = model.groupById.get("g-riverside");
  const neighborhood = model.groupById.get("g-neighborhood");
  const poker = model.groupById.get("g-poker");
  const quartet = model.groupById.get("g-quartet");
  const bridgeId = ivy.members.filter((id) => riverside.members.includes(id))[0];
  const regionAOnly = ivy.members.find((id) => id !== bridgeId);
  const regionBOnly = riverside.members.find((id) => id !== bridgeId);
  // the lurker: sole membership is the 20-member broadcast chat, zero acquaintance edges
  const lurker = neighborhood.members.find(
    (id) => model.membership.get(id).length === 1 && !model.acquaintances.some((e) => e.a === id || e.b === id)
  );
  // the fully isolated person: no group membership at all
  const isolated = model.people.find((p) => model.membership.get(p.id).length === 0).id;
  return { model, bridgeId, regionAOnly, regionBOnly, lurker, isolated, pokerId: poker.id, quartetId: quartet.id };
}

/* ============================================================
   adapt/degrade of RAW
   ============================================================ */
test("adaptRaw drops the user node and every edge that touches it", () => {
  const model = core.adaptRaw(FIXTURE_RAW);
  assert.equal(model.personById.has("user"), false);
  assert.equal(model.groupById.has("user"), false);
  for (const list of model.membership.values()) {
    assert.ok(list.every((m) => m.groupId !== "user"));
  }
  for (const e of model.acquaintances) {
    assert.notEqual(e.a, "user");
    assert.notEqual(e.b, "user");
  }
});

test("adaptRaw builds a group's roster from groupMembership edges, sorted", () => {
  const model = core.adaptRaw(FIXTURE_RAW);
  const poker = model.groupById.get("g-poker");
  assert.equal(poker.members.length, 5);
  assert.deepEqual(poker.members, poker.members.slice().sort());
});

test("adaptRaw degrades to empty acquaintances/fullyAcquaintedChatIds when absent, without throwing", () => {
  const older = cloneRaw();
  delete older.acquaintances;
  delete older.fullyAcquaintedChatIds;
  const model = core.adaptRaw(older);
  assert.deepEqual(model.acquaintances, []);
  assert.equal(model.fullyAcquaintedChatIds.size, 0);
  // the rest of the pipeline must still run end to end on a degraded export
  assert.doesNotThrow(() => {
    const affinity = core.buildAffinity(model);
    const communities = core.assignCommunities(model, affinity);
    const regions = core.labelRegions(model, communities);
    assert.ok(regions.length > 0);
  });
});

test("adaptRaw ignores an acquaintance entry that references an unknown person", () => {
  const bad = cloneRaw();
  bad.acquaintances.push({ a: "nobody-1", b: "nobody-2", tier: "strong", score: 5, evidence: [] });
  const model = core.adaptRaw(bad);
  assert.ok(!model.acquaintances.some((e) => e.a === "nobody-1" || e.b === "nobody-1"));
});

/* ============================================================
   community assignment + region labeling
   ============================================================ */
test("the two dense regions land in different communities, joined by the bridge", () => {
  const { model, bridgeId, regionAOnly, regionBOnly } = findFixtureIds(FIXTURE_RAW);
  const affinity = core.buildAffinity(model);
  const communities = core.assignCommunities(model, affinity);
  assert.notEqual(communities.get(regionAOnly), communities.get(regionBOnly));
  const bridgeCommunity = communities.get(bridgeId);
  assert.ok(bridgeCommunity === communities.get(regionAOnly) || bridgeCommunity === communities.get(regionBOnly));
});

test("a region label is the name of its dominant named group chat", () => {
  const { model, regionAOnly, regionBOnly } = findFixtureIds(FIXTURE_RAW);
  const affinity = core.buildAffinity(model);
  const communities = core.assignCommunities(model, affinity);
  const regions = core.labelRegions(model, communities);
  const regionAResult = regions.find((r) => r.memberIds.includes(regionAOnly));
  const regionBResult = regions.find((r) => r.memberIds.includes(regionBOnly));
  assert.equal(regionAResult.label, "Ivy Study Circle");
  assert.equal(regionBResult.label, "Riverside Alumni");
});

test("a region whose dominant chat is unnamed gets no label", () => {
  const { model, quartetId } = findFixtureIds(FIXTURE_RAW);
  const quartetMembers = model.groupById.get(quartetId).members;
  const affinity = core.buildAffinity(model);
  const communities = core.assignCommunities(model, affinity);
  const regions = core.labelRegions(model, communities);
  const quartetRegion = regions.find((r) => r.memberIds.includes(quartetMembers[0]));
  assert.equal(quartetRegion.label, null);
  assert.equal(quartetRegion.dominantGroupId, quartetId);
});

test("a person with no group membership at all is their own unlabeled region", () => {
  const { model, isolated } = findFixtureIds(FIXTURE_RAW);
  const affinity = core.buildAffinity(model);
  const communities = core.assignCommunities(model, affinity);
  const regions = core.labelRegions(model, communities);
  const region = regions.find((r) => r.memberIds.includes(isolated));
  assert.deepEqual(region.memberIds, [isolated]);
  assert.equal(region.label, null);
});

test("assignCommunities is deterministic: same model and affinity, same result every call", () => {
  const model = core.adaptRaw(FIXTURE_RAW);
  const affinity = core.buildAffinity(model);
  const first = core.assignCommunities(model, affinity);
  const second = core.assignCommunities(model, affinity);
  assert.equal(first.size, second.size);
  for (const [id, label] of first) assert.equal(second.get(id), label);
});

/* ============================================================
   tier recompute for the "everyone here knows each other" toggle
   ============================================================ */
test("checking a chat promotes every pair of its members to confirmed, citing that chat", () => {
  const { model, pokerId } = findFixtureIds(FIXTURE_RAW);
  const members = model.groupById.get(pokerId).members;
  const recomputed = core.recomputeAcquaintances(model.acquaintances, model, new Set([pokerId]));
  const pairCount = (members.length * (members.length - 1)) / 2;
  const pokerPairs = recomputed.filter((e) => members.includes(e.a) && members.includes(e.b));
  assert.equal(pokerPairs.length, pairCount);
  for (const e of pokerPairs) {
    assert.equal(e.tier, "confirmed");
    assert.ok(e.evidence.some((ev) => ev.chatId === pokerId));
  }
});

test("a brand-new pair created by the toggle scores at the confirmed floor", () => {
  const { model, pokerId } = findFixtureIds(FIXTURE_RAW);
  const basePairs = new Set(model.acquaintances.map((e) => [e.a, e.b].sort().join("|")));
  const members = model.groupById.get(pokerId).members;
  const recomputed = core.recomputeAcquaintances(model.acquaintances, model, new Set([pokerId]));
  const brandNew = recomputed.find(
    (e) => members.includes(e.a) && members.includes(e.b) && !basePairs.has([e.a, e.b].sort().join("|"))
  );
  assert.ok(brandNew, "expected at least one pair with no prior acquaintance edge");
  assert.equal(brandNew.score, core.CONFIRMED_MARKER_SCORE);
});

test("unchecking reproduces the base acquaintances exactly -- recompute never mutates its input", () => {
  const { model } = findFixtureIds(FIXTURE_RAW);
  const baseSnapshot = JSON.stringify(model.acquaintances);
  core.recomputeAcquaintances(model.acquaintances, model, new Set(["g-poker"]));
  // the base array itself must be untouched by a "check" call
  assert.equal(JSON.stringify(model.acquaintances), baseSnapshot);
  const revertedAfterCheck = core.recomputeAcquaintances(model.acquaintances, model, new Set());
  const neverChecked = core.recomputeAcquaintances(model.acquaintances, model, new Set());
  assert.deepEqual(revertedAfterCheck, neverChecked);
});

test("promoting a pair that already had evidence from a different chat does not leak into the base", () => {
  // Find a pair that already has an acquaintance edge from some other chat and is
  // also (thinly) in the 20-member broadcast group -- checking g-neighborhood must
  // ADD a second evidence entry on the recomputed copy without appending onto the
  // base edge's own evidence array (a shared-reference mutation would pass this
  // pair's earlier, weaker version of this check but corrupt the base silently).
  const { model } = findFixtureIds(FIXTURE_RAW);
  const neighborhoodMembers = model.groupById.get("g-neighborhood").members;
  const pairBefore = model.acquaintances.find(
    (e) =>
      neighborhoodMembers.includes(e.a) &&
      neighborhoodMembers.includes(e.b) &&
      e.evidence.every((ev) => ev.chatId !== "g-neighborhood")
  );
  assert.ok(pairBefore, "fixture must contain a neighborhood-watch pair whose prior evidence excludes it");
  const evidenceCountBefore = pairBefore.evidence.length;

  const recomputed = core.recomputeAcquaintances(model.acquaintances, model, new Set(["g-neighborhood"]));
  const pairAfter = recomputed.find((e) => e.a === pairBefore.a && e.b === pairBefore.b);
  assert.equal(pairAfter.tier, "confirmed");
  assert.equal(pairAfter.evidence.length, evidenceCountBefore + 1);
  assert.ok(pairAfter.evidence.some((ev) => ev.chatId === "g-neighborhood"));

  // the base model's own copy of this edge must still show only its original evidence
  assert.equal(pairBefore.evidence.length, evidenceCountBefore);
  assert.ok(pairBefore.evidence.every((ev) => ev.chatId !== "g-neighborhood"));
});

test("marksExportPayload emits sorted member ids per checked chat, chats sorted by id", () => {
  const { model } = findFixtureIds(FIXTURE_RAW);
  const payload = core.marksExportPayload(new Set(["g-riverside", "g-family"]), model.groupById);
  assert.deepEqual(Object.keys(payload), ["fullyAcquainted"]);
  assert.equal(payload.fullyAcquainted.length, 2);
  // g-family sorts before g-riverside
  assert.deepEqual(payload.fullyAcquainted[0], model.groupById.get("g-family").members.slice().sort());
  assert.deepEqual(payload.fullyAcquainted[1], model.groupById.get("g-riverside").members.slice().sort());
});

/* ============================================================
   shortest path (pair mode)
   ============================================================ */
test("every acquaintance edge has a positive score, safe for 1/score hop weighting", () => {
  const model = core.adaptRaw(FIXTURE_RAW);
  assert.ok(model.acquaintances.every((e) => e.score > 0));
});

test("a path between the two dense regions exists and passes through the bridge", () => {
  const { model, bridgeId, regionAOnly, regionBOnly } = findFixtureIds(FIXTURE_RAW);
  const adjacency = core.buildAcquaintanceAdjacency(model.acquaintances);
  const result = core.shortestPath(adjacency, regionAOnly, regionBOnly);
  assert.ok(result);
  assert.equal(result.path[0], regionAOnly);
  assert.equal(result.path[result.path.length - 1], regionBOnly);
  assert.ok(result.path.includes(bridgeId));
  assert.ok(result.hops.length > 0);
  assert.ok(result.hops.every((h) => Array.isArray(h.evidence)));
});

test("shortestPath returns null when no acquaintance chain connects the pair", () => {
  const { model, lurker, isolated } = findFixtureIds(FIXTURE_RAW);
  const adjacency = core.buildAcquaintanceAdjacency(model.acquaintances);
  const pokerMember = model.groupById.get("g-poker").members[0];
  assert.equal(core.shortestPath(adjacency, lurker, pokerMember), null);
  assert.equal(core.shortestPath(adjacency, lurker, isolated), null);
});

test("sharedGroupsOf lists a sub-threshold shared chat even when no acquaintance path exists", () => {
  const { model, lurker } = findFixtureIds(FIXTURE_RAW);
  const pokerMember = model.groupById.get("g-poker").members[0];
  const shared = core.sharedGroupsOf(model, lurker, pokerMember);
  assert.ok(shared.some((g) => g.chatId === "g-neighborhood"));
});

test("sharedGroupsOf returns nothing for a pair with no context in common at all", () => {
  const { model, lurker, isolated } = findFixtureIds(FIXTURE_RAW);
  assert.deepEqual(core.sharedGroupsOf(model, lurker, isolated), []);
});

test("shortestPath from a person to themselves is the trivial single-node path", () => {
  const { model, regionAOnly } = findFixtureIds(FIXTURE_RAW);
  const adjacency = core.buildAcquaintanceAdjacency(model.acquaintances);
  assert.deepEqual(core.shortestPath(adjacency, regionAOnly, regionAOnly), {
    path: [regionAOnly],
    hops: [],
    totalWeight: 0
  });
});

/* ============================================================
   stale-mark rejection
   ============================================================ */
test("filterValidMarks keeps a mark whose member key matches the current roster", () => {
  const { model, pokerId } = findFixtureIds(FIXTURE_RAW);
  const key = core.memberKeyOf(model.groupById.get(pokerId).members);
  const kept = core.filterValidMarks([{ chatId: pokerId, memberKey: key, checked: true }], model.groupById);
  assert.equal(kept.length, 1);
  assert.equal(kept[0].checked, true);
});

test("filterValidMarks drops a mark whose member key no longer matches (roster changed)", () => {
  const { model, pokerId } = findFixtureIds(FIXTURE_RAW);
  const staleKey = core.memberKeyOf(["someone-who-left", "someone-new"]);
  const kept = core.filterValidMarks([{ chatId: pokerId, memberKey: staleKey, checked: true }], model.groupById);
  assert.deepEqual(kept, []);
});

test("filterValidMarks drops a mark for a chat that no longer exists in the loaded data", () => {
  const { model } = findFixtureIds(FIXTURE_RAW);
  const kept = core.filterValidMarks(
    [{ chatId: "chat-that-was-merged-away", memberKey: "[]", checked: true }],
    model.groupById
  );
  assert.deepEqual(kept, []);
});

test("effectiveCheckedChatIds: shipped default applies with no marks, an explicit mark overrides it", () => {
  const { model, pokerId, quartetId } = findFixtureIds(FIXTURE_RAW);
  const noMarks = core.effectiveCheckedChatIds(model.fullyAcquaintedChatIds, [], model.groupById);
  assert.ok(noMarks.has(pokerId)); // shipped default: pre-checked

  const uncheckedKey = core.memberKeyOf(model.groupById.get(pokerId).members);
  const uncheckedMark = [{ chatId: pokerId, memberKey: uncheckedKey, checked: false }];
  const afterUncheck = core.effectiveCheckedChatIds(model.fullyAcquaintedChatIds, uncheckedMark, model.groupById);
  assert.ok(!afterUncheck.has(pokerId)); // explicit uncheck wins over the shipped default

  const newKey = core.memberKeyOf(model.groupById.get(quartetId).members);
  const newMark = [{ chatId: quartetId, memberKey: newKey, checked: true }];
  const afterNewCheck = core.effectiveCheckedChatIds(model.fullyAcquaintedChatIds, newMark, model.groupById);
  assert.ok(afterNewCheck.has(quartetId)); // a chat outside the shipped defaults can still be checked
});

/* ============================================================
   top-N label pick
   ============================================================ */
test("topAcquaintanceDegree excludes people with zero acquaintance edges", () => {
  const { model, lurker, isolated } = findFixtureIds(FIXTURE_RAW);
  const top = core.topAcquaintanceDegree(model.people, model.acquaintances, 20);
  assert.ok(!top.includes(lurker));
  assert.ok(!top.includes(isolated));
});

test("topAcquaintanceDegree returns at most N ids, ranked by degree then id", () => {
  const model = core.adaptRaw(FIXTURE_RAW);
  const top = core.topAcquaintanceDegree(model.people, model.acquaintances, 5);
  assert.ok(top.length <= 5);
  const degree = new Map(model.people.map((p) => [p.id, 0]));
  for (const e of model.acquaintances) {
    degree.set(e.a, (degree.get(e.a) || 0) + 1);
    degree.set(e.b, (degree.get(e.b) || 0) + 1);
  }
  for (let i = 1; i < top.length; i++) {
    assert.ok(degree.get(top[i - 1]) >= degree.get(top[i]));
  }
});

/* ============================================================
   bonus: deterministic layout, drawer ordering, display names,
   whole-pipeline smoke test
   ============================================================ */
test("simulateLayout is deterministic: same model and options, identical positions every call", () => {
  const model = core.adaptRaw(FIXTURE_RAW);
  const opts = { iterations: 40 }; // fewer iterations: this test only cares about reproducibility
  const first = core.simulateLayout(model, opts);
  const second = core.simulateLayout(model, opts);
  assert.equal(first.size, second.size);
  for (const [id, p] of first) {
    const q = second.get(id);
    assert.equal(p.x, q.x);
    assert.equal(p.y, q.y);
  }
});

test("compareGroupsForDrawer: named before unnamed is primary, live before dead is secondary", () => {
  const namedDead = { id: "b", name: "Named Dead", isLive: false };
  const namedLive = { id: "a", name: "Named Live", isLive: true };
  const unnamedLive = { id: "c", name: null, isLive: true };
  const order = [unnamedLive, namedDead, namedLive].sort(core.compareGroupsForDrawer);
  assert.deepEqual(order.map((g) => g.id), ["a", "b", "c"]);
});

test("personDisplayName strips a leading guess marker and flags it; null name falls back to id", () => {
  assert.deepEqual(core.personDisplayName({ id: "p1", name: "~Guessed Name" }), { text: "Guessed Name", isGuess: true });
  assert.deepEqual(core.personDisplayName({ id: "p1", name: "Real Name" }), { text: "Real Name", isGuess: false });
  assert.deepEqual(core.personDisplayName({ id: "p1", name: null }), { text: "p1", isGuess: false });
});

test("chatDisplayName falls back to 'unnamed chat of N' only when the name is null", () => {
  assert.equal(core.chatDisplayName(null, 12), "unnamed chat of 12");
  assert.equal(core.chatDisplayName("Trivia Night", 12), "Trivia Night");
});

test("buildViewModel runs the whole pipeline on the fixture without throwing", () => {
  const result = core.buildViewModel(FIXTURE_RAW, []);
  assert.equal(result.model.people.length, 45);
  assert.ok(result.regions.length > 0);
  assert.ok(result.topNames.length > 0);
  assert.ok(result.checkedChatIds.has("g-poker"));
  const layout = core.simulateLayout(result.effectiveModel, { iterations: 20 });
  assert.equal(layout.size, 45);
});
