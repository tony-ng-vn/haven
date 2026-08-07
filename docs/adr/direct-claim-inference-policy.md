# ADR: Direct-claim extraction and inference policy B

Date: 2026-08-06.
Status: accepted (locked founder decision 8, recorded with implementation consequences).

## Decision

The system persists only four kinds of derived knowledge:

1. Raw source evidence (`source_entry_versions.raw_text`, immutable).
2. Directly stated or directly entailed atomic claims (`knowledge_claims`, `derivation_kind = 'direct_extraction'`).
3. Conservative normalized concepts (`knowledge_concepts`, `claim_concepts`).
4. Objective concept relationships (`concept_edges`, e.g. marathon running -> long-distance running -> endurance sport).

Speculative personal conclusions (disciplined, outdoorsy, would be a good accountability partner) are never persisted.
They may be generated at query time, ranked below directly supported facts, labeled as inference, and never written back to storage.
`knowledge_claims.derivation_kind` reserves `query_time_hypothesis` for a future explicit decision; v0 code never writes it.

## Enforcement points

Policy is enforced in code, not by trusting the model:

- The extraction prompt (versioned `extraction-policy-v1`) instructs the model to extract only supported claims, preserve uncertainty and negation, and never infer traits.
- The server-side validator rejects any claim whose evidence quote is not an exact substring of the source, whose offsets do not match, whose predicate is neither registered nor explicitly custom, or whose subject or object references an id the run did not receive.
- The model output schema has no fields for owner, lifecycle, resolution, or derivation kind; those are set by the service.
- Concept edges carry `provenance`; v0 seeds only a small hand-written objective taxonomy (`provenance = 'seed_taxonomy_v1'`), and nothing writes model-generated concept edges.

## Modality, polarity, temporal status

Claims carry three orthogonal qualifiers rather than one merged status:

- `polarity`: `positive` or `negative` ("is not looking for startup introductions" is a negative claim, not an absent one).
- `modality`: `stated`, `uncertain`, `intended` ("might be interested" is `uncertain`; "wants to interview teachers" is `intended` need).
- `temporal_status`: `current`, `historical`, `future` ("used to work at Google" is `historical` `worked_at`).

Search must respect them: a negative claim must never satisfy a positive need query, and a historical `worked_at` must not present as current employment.

## Why not persist inferences with a flag

Rejected because stored inferences rot: the supporting evidence can be revised or deleted while the inference lingers, and ranking "our guess" beside "what you wrote" in one table invites exactly the silent profile mutation decision 8 forbids.
Query-time generation keeps every inference attached to the evidence that produced it at the moment it is shown.
