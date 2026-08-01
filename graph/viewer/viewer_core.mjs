/* Connection graph viewer v4 -- pure core logic.
 *
 * This module is the single source of truth for every non-DOM computation the viewer does: adapting/degrading a RAW export, community + region detection, the "everyone here knows each other" tier recompute, shortest-path pair mode, stale-mark rejection, and the deterministic force layout.
 * tests.mjs imports this file directly and runs under plain `node`, with zero dependencies.
 *
 * build.py inlines this exact file (export keywords stripped, nothing else touched) into template-v4.html's single script block, so the code under test is byte-for-byte the code that ships.
 * See build.py's header comment for the extraction mechanism and how to verify it.
 *
 * No DOM, no canvas, no localStorage, no browser globals of any kind belong in this file -- that is what keeps it runnable under plain `node`.
 * Anything that needs document/window/navigator lives only in template-v4.html's own script, written directly against the functions exported here.
 */
"use strict";

/* ============================================================
   Seeded PRNG
   ============================================================
   Same Numerical Recipes LCG already used by template-v3.html's star field,
   kept identical for house consistency. Deterministic: a given seed always
   produces the same sequence, which is what "two loads of the same file must
   produce the same layout" rests on. */
export function makeRng(seed) {
  let state = (typeof seed === "number" ? seed : 0) >>> 0;
  return function rng() {
    state = (state * 1664525 + 1013904223) % 4294967296;
    return state / 4294967296;
  };
}

// Fixed, arbitrary, and distinct so the two stochastic passes (community
// shuffling, layout jitter) never accidentally correlate with each other.
export const DEFAULT_LAYOUT_SEED = 20260731;
export const DEFAULT_COMMUNITY_SEED = 13072026;

// Ordering used wherever a "keep the strongest tier" decision is needed.
const TIER_RANK = { likely: 0, strong: 1, confirmed: 2 };

/* ============================================================
   RAW adaptation / degrade
   ============================================================
   Turns the exported {nodes, edges, acquaintances?, fullyAcquaintedChatIds?}
   into the shape the rest of this module and the template want. Missing
   acquaintances/fullyAcquaintedChatIds degrade to empty rather than throwing,
   per the DATA CONTRACT: an older export must still render (dots + regions
   from co-membership, no acquaintance lines), never error. */
export function adaptRaw(raw) {
  const rawNodes = Array.isArray(raw && raw.nodes) ? raw.nodes : [];
  const rawEdges = Array.isArray(raw && raw.edges) ? raw.edges : [];
  const rawAcquaintances = Array.isArray(raw && raw.acquaintances) ? raw.acquaintances : [];
  const rawFully = Array.isArray(raw && raw.fullyAcquaintedChatIds) ? raw.fullyAcquaintedChatIds : [];

  const personById = new Map();
  const groupById = new Map();
  // "user" is intentionally never modeled past this point: PLAN.md's Visual
  // contract says the user is implicit, so their node and every edge that
  // touches them are dropped by construction (they simply never enter either
  // map below, and the edge loop after this skips anything that cannot
  // resolve both ends to a known person/group).
  for (const n of rawNodes) {
    if (!n || typeof n.id !== "string") continue;
    if (n.kind === "person") {
      personById.set(n.id, {
        id: n.id,
        name: typeof n.name === "string" ? n.name : null,
        hasContactCard: !!n.hasContactCard,
        degree: typeof n.degree === "number" ? n.degree : 0
      });
    } else if (n.kind === "group") {
      groupById.set(n.id, {
        id: n.id,
        name: typeof n.name === "string" ? n.name : null,
        isLive: !!n.isLive,
        degree: typeof n.degree === "number" ? n.degree : 0,
        members: []
      });
    }
  }

  const membership = new Map();
  for (const id of personById.keys()) membership.set(id, []);

  for (const e of rawEdges) {
    if (!e || e.reason !== "groupMembership") continue;
    const aIsGroup = groupById.has(e.a), bIsGroup = groupById.has(e.b);
    const groupId = aIsGroup ? e.a : (bIsGroup ? e.b : null);
    const personId = aIsGroup ? e.b : (bIsGroup ? e.a : null);
    if (groupId == null || personId == null) continue;
    if (!personById.has(personId) || !groupById.has(groupId)) continue;
    const strength = typeof e.strength === "number" ? e.strength : 0;
    membership.get(personId).push({ groupId, strength });
    groupById.get(groupId).members.push(personId);
  }
  // oneToOneThread and userGroupMembership edges always name "user" on one end
  // (a one-to-one thread is definitionally you plus one other person), so they
  // are excluded above without any special-casing: "user" never entered
  // personById/groupById, so an edge naming it can never resolve both ends.

  for (const g of groupById.values()) g.members.sort();

  // Keyed by pair so a malformed export naming the same pair twice merges rather
  // than silently losing whichever entry a plain array push would have shadowed.
  // PLAN.md's acquaintance layer promises "one acquaintance edge per pair, however
  // many chats underlie it", so a well-formed export never has two; this is a
  // defensive fallback, not the normal path.
  const acquaintanceByPair = new Map();
  for (const a of rawAcquaintances) {
    if (!a || !personById.has(a.a) || !personById.has(a.b) || a.a === a.b) continue;
    const evidence = Array.isArray(a.evidence)
      ? a.evidence.map((ev) => ({
          chatId: ev && typeof ev.chatId === "string" ? ev.chatId : null,
          chatName: ev && typeof ev.chatName === "string" ? ev.chatName : null,
          memberCount: ev && typeof ev.memberCount === "number" ? ev.memberCount : 0,
          coActiveDays: ev && typeof ev.coActiveDays === "number" ? ev.coActiveDays : 0
        }))
      : [];
    const tier = a.tier === "confirmed" || a.tier === "strong" ? a.tier : "likely";
    const score = typeof a.score === "number" && a.score > 0 ? a.score : 0.2;
    const pa = a.a < a.b ? a.a : a.b, pb = a.a < a.b ? a.b : a.a;
    const key = pa + "|" + pb;
    const existing = acquaintanceByPair.get(key);
    if (!existing) {
      acquaintanceByPair.set(key, { a: pa, b: pb, tier, score, evidence });
      continue;
    }
    // Sum scores (PLAN.md: "the score is the sum over all shared chats"), keep the
    // strongest tier seen, union evidence by chat id.
    existing.score += score;
    if (TIER_RANK[tier] > TIER_RANK[existing.tier]) existing.tier = tier;
    for (const ev of evidence) {
      if (!existing.evidence.some((e) => e.chatId === ev.chatId)) existing.evidence.push(ev);
    }
  }
  const acquaintances = [...acquaintanceByPair.values()];

  const fullyAcquaintedChatIds = new Set(rawFully.filter((id) => typeof id === "string" && groupById.has(id)));

  const idOrder = (x, y) => (x.id < y.id ? -1 : x.id > y.id ? 1 : 0);
  return {
    people: [...personById.values()].sort(idOrder),
    groups: [...groupById.values()].sort(idOrder),
    personById,
    groupById,
    membership,
    acquaintances,
    fullyAcquaintedChatIds
  };
}

/* ============================================================
   Display names
   ============================================================ */
// A leading "~" on a name marks a model guess (GraphCore's NodeLabel
// convention, PLAN.md's "always visibly marked as a guess"); strip it for
// display and flag it so the caller can style it distinctly. A null name
// falls back to the raw id, same fallback template-v3.html already used.
export function personDisplayName(person) {
  const raw = person && person.name;
  if (typeof raw === "string" && raw.length > 0) {
    if (raw.charAt(0) === "~") return { text: raw.slice(1), isGuess: true };
    return { text: raw, isGuess: false };
  }
  return { text: (person && person.id) || "", isGuess: false };
}

export function chatDisplayName(name, memberCount) {
  return typeof name === "string" && name.length > 0 ? name : "unnamed chat of " + memberCount;
}

/* ============================================================
   Co-membership + acquaintance affinity, community detection, region labels
   ============================================================
   Each shared chat contributes 1 / (memberCount - 1) to a pair's affinity --
   PLAN.md's own base-weight formula for acquaintance scoring, reused here so a
   large broadcast chat cannot weld unrelated regions together the way a flat
   per-shared-chat weight would. Acquaintance score, when present, adds on top:
   a pair the backend already scored is a stronger signal than co-membership
   alone. */
function shareWeight(memberCount) {
  return 1 / Math.max(1, memberCount - 1);
}

export function buildAffinity(model) {
  const affinity = new Map();
  const add = (i, j, w) => {
    if (i === j || w <= 0) return;
    if (!affinity.has(i)) affinity.set(i, new Map());
    const row = affinity.get(i);
    row.set(j, (row.get(j) || 0) + w);
  };
  for (const g of model.groups) {
    const w = shareWeight(g.members.length);
    for (let i = 0; i < g.members.length; i++) {
      for (let j = i + 1; j < g.members.length; j++) {
        add(g.members[i], g.members[j], w);
        add(g.members[j], g.members[i], w);
      }
    }
  }
  for (const e of model.acquaintances) {
    add(e.a, e.b, e.score);
    add(e.b, e.a, e.score);
  }
  return affinity;
}

// Fisher-Yates over a deterministic rng: reproducible for a fixed seed, but a
// different draw order each pass, which is the standard label-propagation
// trick for avoiding two-community oscillation.
function shuffled(list, rng) {
  const out = list.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    const tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

// Label propagation over the affinity graph. Ties (equal total weight toward
// two different labels) are broken by comparing the label strings, never by
// the rng, so the same input always settles on the same partition regardless
// of how the shuffle order happened to fall.
export function assignCommunities(model, affinity, opts) {
  const maxIters = (opts && opts.maxIters) || 20;
  const rng = makeRng((opts && opts.seed) || DEFAULT_COMMUNITY_SEED);
  const ids = model.people.map((p) => p.id).sort();
  const label = new Map(ids.map((id) => [id, id]));

  for (let iter = 0; iter < maxIters; iter++) {
    const order = shuffled(ids, rng);
    let changed = false;
    for (const id of order) {
      const neighbors = affinity.get(id);
      if (!neighbors || neighbors.size === 0) continue;
      const scoreByLabel = new Map();
      for (const [nb, w] of neighbors) {
        const nbLabel = label.get(nb);
        if (nbLabel === undefined) continue;
        scoreByLabel.set(nbLabel, (scoreByLabel.get(nbLabel) || 0) + w);
      }
      if (scoreByLabel.size === 0) continue;
      const ranked = [...scoreByLabel.entries()].sort((x, y) => (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : 0));
      let best = ranked[0][0], bestScore = ranked[0][1];
      for (let k = 1; k < ranked.length; k++) {
        if (ranked[k][1] > bestScore) { best = ranked[k][0]; bestScore = ranked[k][1]; }
      }
      if (best !== label.get(id)) { label.set(id, best); changed = true; }
    }
    if (!changed) break;
  }
  return label;
}

// Groups people by final label, then picks each region's label from its
// dominant NAMED group chat (most of the region's own members, ties broken by
// smallest group id since model.groups is id-sorted). A region whose dominant
// chat has no name gets no label -- labels are read off evidence, never
// invented.
export function labelRegions(model, communityByPersonId) {
  const membersByCommunity = new Map();
  for (const p of model.people) {
    const c = communityByPersonId.get(p.id);
    if (c === undefined) continue;
    if (!membersByCommunity.has(c)) membersByCommunity.set(c, []);
    membersByCommunity.get(c).push(p.id);
  }
  const groupsById = model.groups.slice().sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const regions = [];
  for (const [communityId, memberIds] of membersByCommunity) {
    memberIds.sort();
    const memberSet = new Set(memberIds);
    let bestGroup = null, bestCount = 0;
    for (const g of groupsById) {
      let count = 0;
      for (const m of g.members) if (memberSet.has(m)) count++;
      if (count > bestCount) { bestCount = count; bestGroup = g; }
    }
    const label = bestGroup && bestGroup.name ? bestGroup.name : null;
    regions.push({ id: communityId, memberIds, dominantGroupId: bestGroup ? bestGroup.id : null, label });
  }
  regions.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return regions;
}

/* ============================================================
   Top-N acquaintance-degree names
   ============================================================
   "Acquaintance degree" is a count of distinct acquaintance-edge neighbors,
   not a weighted sum -- deliberately a simple, legible measure since it only
   drives which ~20 names stay on screen at rest. */
export function topAcquaintanceDegree(people, acquaintances, n) {
  const degree = new Map();
  for (const p of people) degree.set(p.id, 0);
  for (const e of acquaintances) {
    if (degree.has(e.a)) degree.set(e.a, degree.get(e.a) + 1);
    if (degree.has(e.b)) degree.set(e.b, degree.get(e.b) + 1);
  }
  return people
    .map((p) => ({ id: p.id, degree: degree.get(p.id) || 0 }))
    .filter((x) => x.degree > 0)
    .sort((x, y) => y.degree - x.degree || (x.id < y.id ? -1 : x.id > y.id ? 1 : 0))
    .slice(0, n)
    .map((x) => x.id);
}

/* ============================================================
   Marks / "everyone here knows each other" tier recompute
   ============================================================ */
// Canonical key for a group's current roster: JSON-encoding a sorted array
// (rather than joining with a delimiter) so no id's own content can ever be
// mistaken for a separator.
export function memberKeyOf(memberIds) {
  return JSON.stringify(memberIds.slice().sort());
}

// A stored mark survives only if its chat still exists AND its recorded
// member-set key still matches the chat's current roster; a regenerated
// export with a changed roster silently drops the stale mark rather than
// misapplying it to a different set of people.
export function filterValidMarks(marks, groupById) {
  if (!Array.isArray(marks)) return [];
  const out = [];
  for (const m of marks) {
    if (!m || typeof m.chatId !== "string" || typeof m.memberKey !== "string") continue;
    const g = groupById.get(m.chatId);
    if (!g) continue;
    if (memberKeyOf(g.members) !== m.memberKey) continue;
    out.push({ chatId: m.chatId, memberKey: m.memberKey, checked: !!m.checked });
  }
  return out;
}

// Shipped defaults (fullyAcquaintedChatIds) union/overridden by any valid
// explicit mark -- a mark is only ever recorded when the user actually
// toggled a checkbox, so its `checked` value always wins over the default for
// that chat, in either direction.
export function effectiveCheckedChatIds(fullyAcquaintedChatIds, validMarks, groupById) {
  const checked = new Set([...fullyAcquaintedChatIds].filter((id) => groupById.has(id)));
  for (const m of validMarks) {
    if (!groupById.has(m.chatId)) continue;
    if (m.checked) checked.add(m.chatId);
    else checked.delete(m.chatId);
  }
  return checked;
}

// A hand-confirmed pair is treated as more certain than anything scoring
// alone can produce (the "strong" cutoff is 1.0), so it gets a floor above
// that: cheap to traverse in shortest-path's 1/score hop weighting, and never
// lower than a score the pair had already earned on its own.
export const CONFIRMED_MARKER_SCORE = 2;

function pairKey(a, b) {
  return a < b ? a + "|" + b : b + "|" + a;
}

// Pure: never mutates baseAcquaintances or anything reachable from model.
// Re-derives the full effective set from scratch every call, so checking a
// chat and then unchecking it (two independent calls with different
// checkedChatIds) reproduces exactly the base state -- there is no mutable
// intermediate for a bug to leave stale.
export function recomputeAcquaintances(baseAcquaintances, model, checkedChatIds) {
  const byPair = new Map();
  for (const e of baseAcquaintances) {
    const a = e.a < e.b ? e.a : e.b;
    const b = e.a < e.b ? e.b : e.a;
    byPair.set(pairKey(a, b), { a, b, tier: e.tier, score: e.score, evidence: e.evidence.map((ev) => ({ ...ev })) });
  }

  for (const chatId of checkedChatIds) {
    const g = model.groupById.get(chatId);
    if (!g) continue;
    const members = g.members;
    for (let i = 0; i < members.length; i++) {
      for (let j = i + 1; j < members.length; j++) {
        const a = members[i] < members[j] ? members[i] : members[j];
        const b = members[i] < members[j] ? members[j] : members[i];
        const key = pairKey(a, b);
        const existing = byPair.get(key);
        const priorEvidenceForChat = existing ? existing.evidence.find((ev) => ev.chatId === chatId) : null;
        const evidenceEntry = {
          chatId,
          chatName: g.name,
          memberCount: members.length,
          coActiveDays: priorEvidenceForChat ? priorEvidenceForChat.coActiveDays : 0
        };
        if (existing) {
          existing.tier = "confirmed";
          existing.score = Math.max(existing.score, CONFIRMED_MARKER_SCORE);
          if (!priorEvidenceForChat) existing.evidence.push(evidenceEntry);
        } else {
          byPair.set(key, { a, b, tier: "confirmed", score: CONFIRMED_MARKER_SCORE, evidence: [evidenceEntry] });
        }
      }
    }
  }

  return [...byPair.values()].sort((x, y) => (x.a === y.a ? (x.b < y.b ? -1 : 1) : x.a < y.a ? -1 : 1));
}

// The page's own record of what it promoted, exported verbatim as
// {"fullyAcquainted": [[sorted member ids], ...]} for the "copy marks as
// JSON" button.
export function marksExportPayload(checkedChatIds, groupById) {
  const chatIds = [...checkedChatIds].filter((id) => groupById.has(id)).sort();
  return { fullyAcquainted: chatIds.map((id) => groupById.get(id).members.slice().sort()) };
}

/* ============================================================
   Groups drawer ordering
   ============================================================
   Named before unnamed, live before dead, then name then id -- both
   deterministic and readable as "most identifiable, most current first". */
export function compareGroupsForDrawer(g1, g2) {
  const namedRank = (g) => (g.name ? 0 : 1);
  if (namedRank(g1) !== namedRank(g2)) return namedRank(g1) - namedRank(g2);
  const liveRank = (g) => (g.isLive ? 0 : 1);
  if (liveRank(g1) !== liveRank(g2)) return liveRank(g1) - liveRank(g2);
  const n1 = g1.name || "", n2 = g2.name || "";
  if (n1 !== n2) return n1 < n2 ? -1 : 1;
  return g1.id < g2.id ? -1 : g1.id > g2.id ? 1 : 0;
}

/* ============================================================
   Pair mode: shortest path + shared-group fallback evidence
   ============================================================ */
export function buildAcquaintanceAdjacency(acquaintances) {
  const adj = new Map();
  const add = (from, to, e) => {
    if (!adj.has(from)) adj.set(from, []);
    adj.get(from).push({ to, weight: 1 / e.score, tier: e.tier, score: e.score, evidence: e.evidence });
  };
  for (const e of acquaintances) {
    add(e.a, e.b, e);
    add(e.b, e.a, e);
  }
  for (const list of adj.values()) list.sort((x, y) => (x.to < y.to ? -1 : x.to > y.to ? 1 : 0));
  return adj;
}

// Plain O(V^2) Dijkstra: acquaintance graphs here run in the hundreds of
// nodes, so a priority queue buys nothing but complexity. Every acquaintance
// edge has score > 0 by construction (adaptRaw enforces it), so 1/score is
// always finite and positive -- Dijkstra's non-negative-weight precondition
// holds. Deterministic: the frontier always expands the smallest id among
// distance ties, and a strictly-less-than relaxation means whichever edge
// reaches a node first (in that deterministic order) is the one that sticks.
export function shortestPath(adjacency, fromId, toId) {
  if (fromId === toId) return { path: [fromId], hops: [], totalWeight: 0 };
  const dist = new Map([[fromId, 0]]);
  const prevEdge = new Map();
  const visited = new Set();
  for (;;) {
    let currentId = null, currentDist = Infinity;
    for (const [id, d] of dist) {
      if (visited.has(id)) continue;
      if (d < currentDist || (d === currentDist && (currentId === null || id < currentId))) {
        currentDist = d; currentId = id;
      }
    }
    if (currentId === null || currentId === toId) break;
    visited.add(currentId);
    for (const edge of adjacency.get(currentId) || []) {
      if (visited.has(edge.to)) continue;
      const nd = currentDist + edge.weight;
      const existing = dist.has(edge.to) ? dist.get(edge.to) : Infinity;
      if (nd < existing) {
        dist.set(edge.to, nd);
        prevEdge.set(edge.to, { from: currentId, hop: edge });
      }
    }
  }
  if (!dist.has(toId)) return null;
  const hops = [];
  let cursor = toId;
  while (cursor !== fromId) {
    const pe = prevEdge.get(cursor);
    if (!pe) return null;
    hops.unshift({ a: pe.from, b: cursor, tier: pe.hop.tier, score: pe.hop.score, evidence: pe.hop.evidence });
    cursor = pe.from;
  }
  return { path: [fromId, ...hops.map((h) => h.b)], hops, totalWeight: dist.get(toId) };
}

// Fallback for "no observed path": any group chats the two share regardless
// of acquaintance tier, so the panel still has something to point at instead
// of a flat dead end.
export function sharedGroupsOf(model, personAId, personBId) {
  const aGroups = new Set((model.membership.get(personAId) || []).map((m) => m.groupId));
  const shared = (model.membership.get(personBId) || []).filter((m) => aGroups.has(m.groupId));
  return shared
    .map((m) => model.groupById.get(m.groupId))
    .filter(Boolean)
    .map((g) => ({ chatId: g.id, chatName: g.name, memberCount: g.members.length }))
    .sort((x, y) => (x.chatId < y.chatId ? -1 : x.chatId > y.chatId ? 1 : 0));
}

/* ============================================================
   Deterministic force layout
   ============================================================
   Runs synchronously to completion (a fixed iteration count, no timers, no
   wall-clock) so the result is reproducible and the "assembly animation" can
   be a pure visual interpolation toward an already-known destination rather
   than a live physics loop whose outcome depends on frame timing. */
export function initialPositions(people, rng, spread) {
  const pos = new Map();
  for (const p of people) {
    const angle = rng() * Math.PI * 2;
    const radius = spread * Math.sqrt(rng());
    pos.set(p.id, { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius });
  }
  return pos;
}

export function simulateLayout(model, opts) {
  const iterations = (opts && opts.iterations) || 180;
  const seed = (opts && opts.seed) || DEFAULT_LAYOUT_SEED;
  const spread = (opts && opts.spread) || 420;
  const repulsion = (opts && opts.repulsion) || 6000;
  const anchorPull = (opts && opts.anchorPull) || 0.9;
  const springPull = (opts && opts.springPull) || 0.02;
  const springCap = (opts && opts.springCap) || 3;
  const centerPull = (opts && opts.centerPull) || 0.004;

  const rng = makeRng(seed);
  const ids = model.people.map((p) => p.id); // model.people is id-sorted: fixed iteration order
  const pos = initialPositions(model.people, rng, spread);

  for (let iter = 0; iter < iterations; iter++) {
    const force = new Map(ids.map((id) => [id, { x: 0, y: 0 }]));

    // Pairwise repulsion. O(n^2) per iteration; fine for a one-time
    // synchronous layout pass at the hundreds-of-nodes scale PLAN.md measures
    // (~690 people). A quadtree approximation is future tuning, not needed yet.
    for (let i = 0; i < ids.length; i++) {
      const pi = pos.get(ids[i]);
      for (let j = i + 1; j < ids.length; j++) {
        const pj = pos.get(ids[j]);
        let dx = pi.x - pj.x, dy = pi.y - pj.y;
        let d2 = dx * dx + dy * dy;
        if (d2 < 1) d2 = 1;
        const d = Math.sqrt(d2);
        const f = repulsion / d2;
        const fx = (dx / d) * f, fy = (dy / d) * f;
        const fi = force.get(ids[i]), fj = force.get(ids[j]);
        fi.x += fx; fi.y += fy;
        fj.x -= fx; fj.y -= fy;
      }
    }

    // Group anchors: each group's anchor is the centroid of its current
    // members, recomputed every iteration, so no separate physics body is
    // needed for the group itself. Diluted by member count -- same principle
    // as the acquaintance base weight -- so a 20-person broadcast chat barely
    // tugs at all next to a small tight group.
    for (const g of model.groups) {
      if (g.members.length === 0) continue;
      let ax = 0, ay = 0;
      for (const m of g.members) { const p = pos.get(m); ax += p.x; ay += p.y; }
      ax /= g.members.length; ay /= g.members.length;
      const w = (anchorPull * shareWeight(g.members.length)) / g.members.length;
      for (const m of g.members) {
        const p = pos.get(m), f = force.get(m);
        f.x += (ax - p.x) * w;
        f.y += (ay - p.y) * w;
      }
    }

    // Acquaintance springs: tension increases with score, capped so one very
    // high-score pair cannot fling itself out of the map.
    for (const e of model.acquaintances) {
      const pa = pos.get(e.a), pb = pos.get(e.b);
      if (!pa || !pb) continue;
      const dx = pb.x - pa.x, dy = pb.y - pa.y;
      const w = springPull * Math.min(e.score, springCap);
      const fa = force.get(e.a), fb = force.get(e.b);
      fa.x += dx * w; fa.y += dy * w;
      fb.x -= dx * w; fb.y -= dy * w;
    }

    // Gentle centering: repulsion alone has nothing anchoring it to the
    // origin, so the whole map would otherwise drift.
    for (const id of ids) {
      const p = pos.get(id), f = force.get(id);
      f.x -= p.x * centerPull;
      f.y -= p.y * centerPull;
    }

    for (const id of ids) {
      const p = pos.get(id), f = force.get(id);
      p.x += f.x; p.y += f.y;
    }
  }

  return pos;
}

/* ============================================================
   Whole-pipeline entry point
   ============================================================
   The one function the template calls to go from a parsed RAW export plus
   whatever marks localStorage held to everything rendering needs. Keeping
   this wiring here (rather than re-assembled ad hoc in the template) is part
   of what keeps the shipped code identical to the tested code. */
export function buildViewModel(raw, storedMarksRaw, opts) {
  const model = adaptRaw(raw);
  const validMarks = filterValidMarks(storedMarksRaw, model.groupById);
  const checkedChatIds = effectiveCheckedChatIds(model.fullyAcquaintedChatIds, validMarks, model.groupById);
  const acquaintances = recomputeAcquaintances(model.acquaintances, model, checkedChatIds);
  const effectiveModel = { ...model, acquaintances };
  const affinity = buildAffinity(effectiveModel);
  const communityByPersonId = assignCommunities(effectiveModel, affinity, opts && opts.community);
  const regions = labelRegions(effectiveModel, communityByPersonId);
  const topNames = topAcquaintanceDegree(model.people, acquaintances, (opts && opts.topN) || 20);
  const adjacency = buildAcquaintanceAdjacency(acquaintances);
  return {
    model,
    effectiveModel,
    validMarks,
    checkedChatIds,
    acquaintances,
    affinity,
    communityByPersonId,
    regions,
    topNames,
    adjacency
  };
}
