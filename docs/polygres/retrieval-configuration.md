# Polygres retrieval configuration for haven_knowledge

Date: 2026-08-06.
Companion evidence: docs/polygres/development-validation.md (what was tested and observed).

## Text

`haven_retrieval_text`, tsvector over `haven_knowledge.retrieval_items.retrieval_tsv` (a stored generated column: `to_tsvector('simple', retrieval_text)`), language `simple`, row id `id`, filters `owner_id`, `lifecycle_status`, `primary_entity_id`, `item_kind`.

The parser decision, recorded:

- The config language must match the column's generation parser; mismatch silently loses morphological variants (observed and documented in development-validation.md).
- `simple` is the primary configuration. Reasons: the corpus is names, handles, mixed English-Vietnamese notes, and short claim renderings; english stemming of names and non-English tokens creates false matches the product cannot explain, and the retrieval evaluation reached recall@5 = 1.0 on `simple` once two compensations were in place: claim retrieval text carries taxonomy concept names (so "endurance sport" matches lexically), and zero-hit queries retry as per-term runtime queries fused with RRF (so AND semantics cannot zero out a query over a missing stopword).
- `haven_retrieval_text_english` (over the twin generated column `retrieval_tsv_english`) is retained for future A/B measurement; it stems plurals and gerunds ("marathon" matches "marathons") at the cost of name and mixed-language fidelity. Nothing in the application queries it today.

## Fuzzy

`haven_entity_name_fuzzy` over `haven_knowledge.knowledge_entities.normalized_name`, filters `owner_id`, `entity_state`, `entity_type`.
Used by the fast name path and by reference-candidate suggestion.
One-transposition typos match at the default threshold; heavier corruption misses, and the SQL trigram fallback behaves the same way by construction.

## Vector

`haven_retrieval_embedding` over `haven_knowledge.retrieval_items.embedding`, 1024 dimensions, cosine, hnsw, row id `id`, filters `owner_id`, `lifecycle_status`, `primary_entity_id`, `item_kind`.

Embedding contract (documented change): `voyage-3.5` at 1024 dimensions via the Voyage API, because the repository's OpenAI embedding key was dead at build time and interfaze serves no embeddings endpoint.
The provider layer falls back to OpenAI `text-embedding-3-small`/1536 if `VOYAGE_API_KEY` is absent but a valid `OPENAI_API_KEY` exists; dimensions and model travel together and are recorded per row (`embedding_model`, `embedding_dimensions`, `embedding_input_hash`).
The knowledge domain's 1024 is independent of the public mirror's 1536 configs; they are separate configs over separate tables.
Query embeddings always use the same provider and dimensions as indexed rows; `embed_text` validates dimension and finiteness before anything is written or queried.

## Graph

Registered into the existing project graph configuration (merged, never replaced): nodes `haven_knowledge.knowledge_entities` (tenant column `owner_id`), relationships from `haven_knowledge.entity_relations.subject_entity_id` and `.object_entity_id` to `knowledge_entities.id`.
Deliberately not registered: `haven_users`, `auth_identities`, `knowledge_outbox`, `knowledge_claims`, and every `owner_id` foreign key -- tenancy is a filter, never a traversal edge.
Depth policy: 1 by default, 2 maximum for v0.

Status: configuration applies and reports ready, but the platform's projection build queue has never run on this project (see development-validation.md), so data-plane traversal fails project-wide.
Until that is fixed platform-side, the relationship path answers from relational claims over `entity_relations`/`knowledge_claims` (identical data) and reports a graph coverage warning.

## Fusion

General people search runs lexical and vector concurrently and fuses in Haven with reciprocal rank fusion (k=60), deduplicating by canonical primary entity (provisional entities resolved one hop; unresolved provisionals stay separate and qualified).
There is no server-side text-plus-vector endpoint; this is by platform design and handled in `knowledge/src/haven_knowledge/retrieval.py`.
