# ADR: Provisional entities and deliberate reference resolution

Date: 2026-08-06.
Status: accepted (locked founder decisions 5 and 6, recorded with implementation consequences).

## Decision

A person mentioned in a source entry whose canonical identity is unknown becomes a `knowledge_entities` row with `entity_state = 'provisional'`.
It is a real graph node: claims can point at it, relations can traverse it, and recall can cite it with qualification.
It is not a directory person: it has no `convex_person_id`, it never appears in directory-shaped listings, and it is excluded from any surface that implies a confirmed identity.

## What a provisional reference retains

The provisional entity row holds owner, display name (the mention as written), normalized name, and resolution state.
The `entity_mentions` row created alongside it holds the source entry version, the exact surface text, validated character offsets, and the mention role.
The claim that connects it to the primary person (for example `introduced_by`) holds the evidence quote and offsets.
Together these satisfy decision 5's retention list without duplicating evidence into the entity row.

## Resolution rules

- Name similarity may produce candidate suggestions (fuzzy retrieval over `normalized_name`), never resolution.
- Automatic resolution requires deterministic identity evidence: a stable platform id, verified phone or email, an explicit user confirmation, or an equivalent unique identifier.
  v0 implements only explicit confirmation through `resolveReference`; the deterministic-import path is reserved.
- `reference_candidate_decisions` records `confirmed`, `rejected`, and `not_sure` per (provisional, candidate) pair with a `candidate_context_hash`.
  A rejected pair is suppressed from future suggestion lists unless the hash changes, which is what "meaningful new evidence" means operationally: new active evidence rows involving the provisional entity produce a different hash.
- Confirmation sets `resolved_to_entity_id` and `resolution_status = 'confirmed'` on the provisional row.
  The row is never deleted and never merged away: historical claims keep pointing at it, and reads follow `resolved_to_entity_id` one step to present the canonical identity.
  One step only, enforced by a check that a canonical entity cannot itself carry `resolved_to_entity_id`, so chains cannot form.

## Why keep the provisional node after resolution

Rewriting claims to point at the canonical entity would destroy the historical record of what the user actually wrote ("Alex" the ambiguous mention, later resolved).
Decision 6 requires preserving the provisional node and original evidence; the one-hop pointer gives canonical-entity reads at the cost of a single join.

## Out of scope for v0

The user-facing resolution inbox.
The backend contract (`listReferenceCandidates`, `resolveReference`, `rejectReferenceCandidate`, `markReferenceNotSure`) exists and is tested; no UI consumes it yet.
