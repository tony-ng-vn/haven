# ADR: Source entries and immutable versions

Date: 2026-08-06.
Status: accepted.

## Decision

A raw memory is stored as a stable `source_entries` row (identity, scope, primary entity, lifecycle) plus one immutable `source_entry_versions` row per revision.
`raw_text` never changes after insert; a revision inserts version N+1, repoints `current_version_id`, and marks every derived row of version N superseded.
All derived data (mentions, claims, relations, retrieval items) points at both the entry and the exact version that produced it.

## Why versions instead of in-place edits

- Decision 3 requires preserving raw evidence exactly and reprocessing later with better extractors; both need the original text to survive edits.
- Decision 7's evidence offsets are only meaningful against an immutable string.
- Question 7 (final memory UI) is unresolved; the entry/version split is the shape that supports all three candidate UIs without a schema redesign (see docs/product/question-7-compatibility.md).

## Lifecycle semantics

- Entry lifecycle: `active`, `deleted`.
- Claim lifecycle: `active`, `superseded`, `deleted`, `invalid`.
- Revision: old version's claims become `superseded`; relations and retrieval items derived from them are deactivated in the same transaction; historical versions remain readable for audit.
- Deletion: the entry and every version, claim, relation, mention, and retrieval item are marked deleted in one transaction; provisional entities whose last active support disappears are marked deleted too.
  Deleted rows keep their ids so audits can prove what was removed, but no retrieval surface, graph registration, or API response may include them.

## Alternatives rejected

- Mutable `raw_text` with an audit log: loses offset integrity and makes reprocessing dependent on log replay.
- Hard-deleting derived rows on revision: destroys extraction provenance and makes "what did we used to believe" unanswerable; soft lifecycle states cost one indexed column.
- Event sourcing the whole domain: more machinery than a v0 with one writer needs; the outbox already gives the async pipeline durability.
