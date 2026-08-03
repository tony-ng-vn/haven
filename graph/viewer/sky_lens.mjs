/* sky_lens.mjs -- pure selection logic for the sky's connection lens (double-click a
 * person to see who THEY know). No DOM, no canvas, no globals: callers own how the
 * result gets drawn. Tested standalone with plain `node` (see sky_lens.tests.mjs);
 * inlined into template-sky.html by build.py / SkyExportBuilder through the same
 * conditional core-placeholder seam viewer_core.mjs used to fill.
 *
 * Every top-level `export` below must stay at column 0 (no leading whitespace): the
 * inliner strips the `export ` keyword with a regex anchored to the start of the line,
 * so an indented export would survive as a syntax error in the classic <script> it
 * lands in.
 */
"use strict";

/// Everyone the focused person knows, per the export's acquaintance layer, each marked
/// by whether they ALSO connect straight to you (a real one-to-one thread edge), or are
/// known to you only through shared groups. Returns [] whenever there is nothing
/// meaningful to show: no focus, the user themselves (never lensable -- acquaintance
/// pairs are always between two people, never the user), a focus id absent from this
/// export, or an export that predates the acquaintances field entirely.
///
/// `acquaintances`/`edges` are the export's own raw arrays (GraphJSON's `a`/`b`/`tier`
/// and `a`/`b`/`reason` shapes) -- this function does its own deleted/absent filtering
/// from `deletedIds`/`nodeIds` rather than trusting a caller to have pre-filtered either
/// array, so the result stays correct regardless of what shape the caller's own adapted
/// model happens to be in.
export function computeLens(focusedPersonId, acquaintances, edges, deletedIds, nodeIds) {
  if (!focusedPersonId || focusedPersonId === "user") return [];
  if (!Array.isArray(acquaintances) || acquaintances.length === 0) return [];

  const nodeSet = toSet(nodeIds);
  const deletedSet = toSet(deletedIds);
  if (!nodeSet.has(focusedPersonId) || deletedSet.has(focusedPersonId)) return [];

  // A one-to-one thread edge naming "user" and this id is the export's own definition
  // of "connects directly to you" -- the same edge reason GraphBuilder gives a real
  // one-to-one iMessage/SMS thread, never a group membership.
  const directToYouIds = new Set();
  for (const e of Array.isArray(edges) ? edges : []) {
    if (!e || e.reason !== "oneToOneThread") continue;
    if (e.a === "user" && e.b) directToYouIds.add(e.b);
    else if (e.b === "user" && e.a) directToYouIds.add(e.a);
  }

  const result = [];
  const seen = new Set();
  for (const acq of acquaintances) {
    if (!acq) continue;
    let neighborId = null;
    if (acq.a === focusedPersonId) neighborId = acq.b;
    else if (acq.b === focusedPersonId) neighborId = acq.a;
    else continue;
    if (!neighborId || neighborId === focusedPersonId) continue;
    if (deletedSet.has(neighborId) || !nodeSet.has(neighborId)) continue;
    if (seen.has(neighborId)) continue;   // one entry per pair in a well-formed export; defensive only
    seen.add(neighborId);
    // interactionCount defaults to 0 for an export that predates the field (or, defensively,
    // any acquaintance entry missing it) -- never undefined, so a caller's `>= 3` comparison
    // never has to special-case "field absent" as distinct from "field present and zero".
    result.push({
      neighborId,
      tier: acq.tier,
      directToYou: directToYouIds.has(neighborId),
      interactionCount: acq.interactionCount || 0
    });
  }
  return result;
}

function toSet(value) {
  if (value instanceof Set) return value;
  return new Set(Array.isArray(value) ? value : []);
}

/// Acquaintance pairs BETWEEN two of the lens's OWN neighbors -- never involving the
/// lensed person themselves, whose own edges to each neighbor are computeLens's job.
/// This is what answers "does C know A" when lensing B reveals both A and C: the
/// export already carries that A-C pair if any evidence exists (co-membership or a
/// direct thread produces its own acquaintance entry regardless of B), so this is a
/// second read of the SAME acquaintances array, not a new signal.
///
/// `neighborIds` is expected to already be filtered (deleted/absent removed), the same
/// contract computeLens's own result already satisfies -- this function does no
/// filtering of its own beyond checking BOTH ends are in the given set.
export function computeLensMesh(neighborIds, acquaintances) {
  const idSet = toSet(neighborIds);
  if (idSet.size < 2) return [];
  if (!Array.isArray(acquaintances) || acquaintances.length === 0) return [];

  const seen = new Set();
  const result = [];
  for (const acq of acquaintances) {
    if (!acq || acq.a === acq.b) continue;
    if (!idSet.has(acq.a) || !idSet.has(acq.b)) continue;
    const key = acq.a < acq.b ? acq.a + "|" + acq.b : acq.b + "|" + acq.a;
    if (seen.has(key)) continue;   // one entry per pair in a well-formed export; defensive only
    seen.add(key);
    // Same zero-default as computeLens's own interactionCount -- see its doc comment.
    result.push({ a: acq.a, b: acq.b, tier: acq.tier, interactionCount: acq.interactionCount || 0 });
  }
  return result;
}
