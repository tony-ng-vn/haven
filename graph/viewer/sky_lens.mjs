/* sky_lens.mjs -- the sky's pure, dependency-free viewer-core logic: no DOM, no canvas,
 * no globals, callers own how any result gets drawn or rendered. Tested standalone with
 * plain `node` (see sky_lens.tests.mjs); inlined into template-sky.html by build.py /
 * SkyExportBuilder through the viewer-core placeholder seam (see build.py's own header
 * comment for that placeholder's exact name -- not spelled out literally in this file,
 * since this file's own text is what gets inlined in its place).
 *
 * Two unrelated concerns share this one file rather than a second inliner seam, which
 * build.py's own CORE_FILENAME constant supports only one of at a time:
 *   - the connection lens (double-click a person to see who THEY know) -- computeLens,
 *     computeLensMesh;
 *   - name-disambiguator label formatting (two dots sharing the exact same display name,
 *     GraphJSON's `disambiguator` field) -- formatPersonLabel.
 * The placeholder seam itself was always this generic; only this file's OWN header
 * comment used to describe it as lens-specific.
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

/// A person's rendered name, plus an optional quieter suffix distinguishing them from
/// another exported node sharing the exact same display name (GraphJSON's `disambiguator`
/// field -- e.g. two different "John"s, present only when a real collision exists). Every
/// falsy shape a missing field can take -- absent, undefined, null, or an empty string --
/// collapses to the SAME { suffix: null } result: an export built before this field existed,
/// or a unique name, must render identically to today, never a literal "undefined" string
/// stitched into a label.
export function formatPersonLabel(name, disambiguator) {
  const suffix = (typeof disambiguator === "string" && disambiguator.length > 0) ? disambiguator : null;
  return { name, suffix };
}

/// The sky's one label-resolution rule: a user-typed custom name wins over everything,
/// then a real (contact-card) name, then a model guess (tilde-stripped), then the raw id
/// as a last resort. `labelKind` is "custom"/"name"/"guess"/"phone" respectively -- the
/// same four-state vocabulary template-sky.html already styles by (only "guess" and
/// "phone" render dim/uncertain; a custom name is a deliberate, confident choice and
/// reads exactly like a real name).
///
/// A custom name that happens to collide with another displayed name is not this
/// function's problem: the export's `disambiguator` field is keyed to the PERSON, not to
/// whichever name string happens to be showing, so a caller who already has one just
/// passes this function's `name` straight into formatPersonLabel(name, disambiguator) --
/// no special-casing needed here or there.
export function resolvePersonLabel(rawName, customName, fallbackId) {
  const trimmedCustom = typeof customName === "string" ? customName.trim() : "";
  if (trimmedCustom) return { name: trimmedCustom, labelKind: "custom" };
  if (rawName && rawName.startsWith("~")) return { name: rawName.slice(1), labelKind: "guess" };
  if (rawName) return { name: rawName, labelKind: "name" };
  return { name: fallbackId, labelKind: "phone" };
}

/// The pure heart of loadEdits: given whatever JSON.parse handed back for the
/// localStorage payload (or null/undefined for "nothing stored yet"), returns a safe
/// { v, moves, deleted, names } shape. localStorage access, JSON.parse itself, and the
/// try/catch around a throwing storage backend all stay in template-sky.html -- this
/// function only ever sees plain, already-parsed values (or the absence of one).
///
/// `names` (custom renames, keyed by person id) is additive to the existing v1 shape: a
/// payload saved before renaming existed simply lacks the key, which is a normal, valid
/// v1 payload, not an "unknown shape" -- it must load fine and keep its real moves/deleted,
/// never fall through to the reset-to-empty branch below just because one newer key is
/// absent.
export function normalizeEditsPayload(parsed) {
  const empty = { v: 1, moves: {}, deleted: [], names: {} };
  if (!parsed || parsed.v !== 1) return empty;
  return {
    v: 1,
    moves: (parsed.moves && typeof parsed.moves === "object") ? parsed.moves : {},
    deleted: Array.isArray(parsed.deleted) ? parsed.deleted : [],
    names: (parsed.names && typeof parsed.names === "object") ? parsed.names : {}
  };
}
