# Question 7 compatibility: how the schema supports all three memory UIs

Question 7 (the user-facing memory representation) is deliberately unresolved.
This document proves the source-entry model supports every candidate answer without a destructive schema change, so deciding later costs nothing structural.

The three candidates:

- A. One mutable profile note per person.
- B. Separate timestamped memories per person.
- C. Timestamped memories plus a generated current summary.

## The invariant shape

A memory is a `source_entries` row (stable identity, scope, primary person) with immutable `source_entry_versions` rows underneath it and `current_version_id` pointing at the live one.
Nothing in the product-facing interface assumes how many entries a person has or how often a version changes.

## Option A: one mutable note

One logical entry per person, many versions.
The note editor maps "save" to `reviseSourceEntry`: each save inserts version N+1, supersedes the derived rows of version N, and re-extracts.
The UI reads `current_version_id.raw_text` as the note body.
Nothing else changes: extraction, retrieval items, and claims already key on (entry, version).
The old versions double as the note's edit history, which option A products usually end up wanting anyway.

## Option B: separate timestamped memories

Many entries per person, each typically holding one version.
"Add memory" maps to `createSourceEntry`; editing one memory maps to `reviseSourceEntry` on that entry alone; deleting one maps to `deleteSourceEntry`.
`captured_at` on the version is the display timestamp.
The list view is `source_entries where primary_entity_id = person and lifecycle_status = 'active' order by created_at`.

## Option C: memories plus generated summary

Option B's write model unchanged, plus a derived projection.
`retrieval_items.item_kind` already reserves `person_summary`: a background job would compose active claims into a summary row with `lifecycle_status` tied to its inputs, regenerated when any input changes.
The summary is derived and disposable, never evidence: deleting it loses nothing, and no claim may cite it.
v0 deliberately does not implement the generator; the reserved item kind and the claims it would read from are the compatibility guarantee.

## What would actually differ per option

Only interface-layer policy:

- how many active entries the UI creates per person (A: exactly one; B and C: many);
- which timestamps are shown;
- whether the summary job runs (C only).

No table, column, constraint, index, or retrieval configuration differs between the three.
That is the whole point of paying for the entry/version split now.

## The one rule that must hold until the decision

The existing Convex note editor stays wired to Convex `people.context`.
Wiring it to `createSourceEntry` or `reviseSourceEntry` before question 7 is decided would silently commit the product to A or B semantics.
The developer vertical slice exists precisely so the pipeline can be exercised without touching that editor.
