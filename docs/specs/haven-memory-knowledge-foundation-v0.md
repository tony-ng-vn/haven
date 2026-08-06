# Haven Memory Knowledge Foundation v0

Date: 2026-08-06.
Status: implemented behind flags; see the final section for what is deliberately open.

## Goals

- Give Haven one evidence-preserving store for what the user writes about people: raw entries, versions, extracted claims, provisional references, concepts, and retrieval items, owned by Polygres (project `pa6ee1830f10557dcc9bfd0c`, schema `haven_knowledge`).
- Make raw text searchable the moment it is captured, and extracted claims searchable the moment extraction succeeds, without the capture path ever waiting on a model.
- Keep every derived row traceable to an exact evidence quote in an immutable source version, revocable by revision or deletion.
- Support all three question-7 memory UIs (one note, many memories, memories plus summary) with one schema.
- Prove the whole path end to end with a developer vertical slice, integration tests against the real managed database, and a repeatable retrieval evaluation.

## Non-goals (v0)

Final memory UI; global (non-person-anchored) capture UI; proactive matching; needs-to-offers recommendations; automated introductions; cross-user discovery; automatic identity merging by name; the reference-review inbox UI; fine-tuning; persisted personality inference; bulk Convex migration; end-to-end encryption; any production traffic switch.

## Locked decisions

Recorded in ADRs, summarized: Polygres owns the knowledge domain (docs/adr/knowledge-authority-polygres.md); a Python knowledge service is the server boundary (docs/adr/knowledge-service-boundary.md); source entries are versioned and immutable (docs/adr/source-entry-versioning.md); inference policy B (docs/adr/direct-claim-inference-policy.md); provisional references resolve deliberately (docs/adr/provisional-identity-resolution.md).
Convex stays authoritative for the application shell; a person mirrors into `knowledge_entities` with `convex_person_id` as an opaque external mapping.
Clients never supply `owner_id`; the service resolves Clerk identity (provider, issuer, subject) to a stable `haven_users.id` UUID through `auth_identities`.

## Terminology

- Owner: a `haven_users` row; every tenant-owned row carries `owner_id`.
- Source entry: the stable identity of one raw memory; scope is `person_anchored` (v0) or `global` (reserved).
- Source version: one immutable text of the entry; the entry points at its current version.
- Claim: one atomic subject-predicate-object statement with evidence, qualifiers, and lifecycle.
- Entity: a canonical or provisional node in `knowledge_entities`; canonical people carry `convex_person_id`.
- Mention: an occurrence of an entity in a version's text with validated offsets.
- Relation: the graph projection of an entity-to-entity claim; never independent truth.
- Concept: a normalized topic (`marathon running`); concept edges form a small objective taxonomy.
- Retrieval item: one row in the unified retrieval surface (`raw_source` or `direct_claim` in v0), carrying the searchable text and optional embedding.
- Outbox job: one durable unit of background work with an idempotency key.

## Data model

Schema `haven_knowledge`, UUID primary keys via `gen_random_uuid()`, timestamps as `timestamptz`.
Tables (full DDL in `knowledge/migrations/0001_haven_knowledge_core.sql`):

- `haven_users` (id, created_at, updated_at).
- `auth_identities` (haven_user_id FK, provider, issuer, provider_subject; unique(provider, issuer, provider_subject)).
- `knowledge_entities` (owner_id, entity_type check-constrained to a known list starting with `person`, entity_state `canonical|provisional`, display_name, normalized_name, convex_person_id nullable, resolved_to_entity_id nullable self-FK, resolution_status nullable, deleted_at; checks: canonical rows have no resolution fields, provisional rows have no convex_person_id).
- `source_entries` (owner_id, scope `person_anchored|global`, primary_entity_id nullable FK, source_type text with named known values but no enum lock, current_version_id nullable FK, lifecycle_status `active|deleted`; check: person_anchored requires primary_entity_id).
- `source_entry_versions` (owner_id, source_entry_id FK, version_number, raw_text, captured_at, supersedes_version_id nullable FK, content_hash, lifecycle `active|superseded|deleted`, lifecycle timestamps; unique(source_entry_id, version_number); raw_text immutability enforced by trigger).
- `extraction_runs` (owner_id, source_entry_id, source_entry_version_id, extraction_policy_version, prompt_version, model_provider, model_name, status `pending|running|succeeded|failed`, attempt_count, started_at, completed_at, error_code, safe_error_message).
- `entity_mentions` (owner_id, source_entry_version_id, entity_id, surface_text, normalized_surface_text, evidence_start, evidence_end, mention_role `primary|subject|object|contextual`, lifecycle `active|superseded|deleted`, lifecycle timestamps).
- `knowledge_claims` (owner_id, source_entry_id, source_entry_version_id, extraction_run_id, subject_entity_id, predicate_key, custom_predicate_label nullable, object_entity_id nullable, object_text nullable, object_value_json nullable, polarity `positive|negative`, modality `stated|uncertain|intended`, temporal_status `current|historical|future`, confidence 0..1, evidence_quote, evidence_start, evidence_end, derivation_kind `direct_extraction` (+reserved values), lifecycle_status `active|superseded|deleted|invalid`, superseded_at, deleted_at; check: at least one object representation present).
- `entity_relations` (owner_id, source_claim_id FK, subject_entity_id, predicate_key, object_entity_id, lifecycle_status, confidence, deleted_at).
- `knowledge_concepts` (concept_key unique, display_name, concept_type).
- `concept_edges` (source_concept_id, relationship_key, target_concept_id, provenance; unique triple).
- `claim_concepts` (owner_id, claim_id, concept_id, mapping_type `normalized|exact|taxonomy_parent`, confidence).
- `retrieval_items` (owner_id, primary_entity_id, item_kind `raw_source|direct_claim` (+reserved), source_entry_id, source_entry_version_id, claim_id, concept_id, retrieval_text, text_hash, retrieval_tsv generated always from `to_tsvector('simple', retrieval_text)`, embedding vector(1024) nullable, embedding_model, embedding_dimensions, embedding_input_hash, embedding_status `pending|ready|failed|skipped`, lifecycle_status, deleted_at).
- `knowledge_outbox` (owner_id, job_type `extract_source|embed_retrieval_item|project_graph|deactivate_superseded_version`, source_entry_id, source_entry_version_id, idempotency_key unique, payload jsonb, status `pending|running|succeeded|failed|dead`, attempt_count, available_at, locked_at, locked_by, completed_at, last_error_code).
- `reference_candidate_decisions` (owner_id, provisional_entity_id, candidate_entity_id, decision `confirmed|rejected|not_sure`, candidate_context_hash, decided_by; unique(provisional_entity_id, candidate_entity_id)).

Indexes: owner on every tenant table; (owner, lifecycle); (owner, primary_entity) on retrieval items and entries; (source_entry, version_number); version on mentions and claims; subject and object entity on claims and relations; normalized_name; unresolved provisional partial index; outbox (status, available_at); GIN on retrieval_tsv; HNSW on embedding (via the Polygres vector config); trigram on normalized_name (via the fuzzy config).
`owner_id` columns are plain FK columns to `haven_users` and are excluded from graph registration, so tenancy never becomes a traversal edge.

## State transitions

Source entry: `active -> deleted` (terminal).
Version: created immutable; never mutates; version N is logically superseded when N+1 exists.
Claim: `active -> superseded` (revision), `active|superseded -> deleted` (source deletion), `active -> invalid` (reserved for validator retro-runs).
Relation: mirrors its claim in the same transaction.
Retrieval item: `active -> superseded|deleted`; embedding_status `pending -> ready|failed` independent of lifecycle.
Outbox job: `pending -> running -> succeeded|failed`, failed retries with exponential backoff until `dead`.
Provisional entity: `unresolved -> confirmed` (sets resolved_to_entity_id) or stays; deleted when its last active support disappears.

## Processing pipeline

Synchronous capture transaction (one BEGIN/COMMIT on the pooled connection):
authenticate; resolve owner; validate primary person (owner-scoped canonical entity); insert entry + version 1; point current_version_id; insert the `raw_source` retrieval item (immediately text-searchable through the generated tsvector); insert `extract_source` and `embed_retrieval_item` outbox jobs with deterministic idempotency keys; return ids, request id, and `raw_searchable: true`.

Background worker (separate process, separate connection, bounded concurrency per job type):
claims jobs with `FOR UPDATE SKIP LOCKED` where `status='pending' and available_at <= now()`;
`extract_source` runs the versioned extractor, validates output, and in one transaction inserts mentions, provisional entities, claims, relations, and `direct_claim` retrieval items, then enqueues their embedding jobs;
`embed_retrieval_item` fetches the item, skips if the input hash already matches, calls the embedding provider, writes the vector;
`project_graph` is a no-op placeholder in v0 because relations are graph-registered tables (see retrieval design) and freshness is handled at configuration level;
`deactivate_superseded_version` exists for revision cleanup done asynchronously when a revision transaction chose to defer it (v0 does it synchronously; the job type is reserved).
Failures record safe error codes only; raw text and model payloads are never logged.

## Domain interface

`knowledge/src/haven_knowledge/service.py` exposes the stable operations:
`create_source_entry`, `revise_source_entry`, `delete_source_entry`, `get_source_entry`, `get_person_knowledge`, `search_network`, `list_reference_candidates`, `resolve_reference`, `reject_reference_candidate`, `mark_reference_not_sure`, `get_processing_status`, plus `ensure_owner` (identity) and `mirror_convex_person` (canonical-entity mirror).
Every operation takes an `AuthContext` (provider, issuer, subject) resolved server-side to `owner_id`; none accepts `owner_id` from outside.
Create accepts convex person id or canonical entity id, raw text, source type, captured_at, and an idempotency key, and returns entry id, version id, primary entity, processing status, raw retrieval availability, and request id.
Search returns canonical entities with convex person ids, fused score, result type, evidence with source ids and claim ids, contributing strategies, unresolved references with qualification text, and coverage warnings; embeddings are never exposed.
An HTTP transport can wrap these one-to-one later; v0 ships the library plus the developer CLI (`knowledge/README.md` documents the commands).

## Retrieval design

- Text: Polygres tsvector config over `retrieval_items.retrieval_tsv` (simple parser; an english-parser twin column exists for the recorded comparison, see docs/polygres/retrieval-configuration.md).
- Fuzzy: config over `knowledge_entities.normalized_name` for person-name lookup and candidate suggestion.
- Vector: config over `retrieval_items.embedding`, 1024-dim cosine (`voyage-3.5`, with `text-embedding-3-small` shortened to 1024 as fallback), with owner_id, lifecycle_status, and primary_entity_id as filter columns.
- Graph: `knowledge_entities` registered as nodes and `entity_relations` as the relationship table (subject and object FKs), tenant column owner_id; haven_users, auth_identities, outbox, and audit tables are never registered.
- Hybrid people search: run tsvector and vector retrieval concurrently, fuse with reciprocal rank fusion (k=60), deduplicate by canonical primary entity (following provisional resolution one hop), hydrate active evidence, and re-check ownership on every hydrated row.
- Relationship queries: deterministic router; graph or relational claim lookup bounded to depth 1 (2 max); unresolved endpoints answered with explicit qualification and the resolution action contract.
- Query router: fast path (exact and fuzzy name, id lookup, no model call); standard path (lexical + vector + fusion); relationship path (predicate-shaped questions).
  v0 routes with deterministic heuristics and renders answers deterministically; no generative model sits between retrieval and the response.

## Authorization boundaries

Owner resolution happens server-side per call.
Every SQL statement on tenant tables carries `owner_id = %s` from the resolved context.
Runtime API filters include owner_id but are treated as candidate narrowing only; hydration re-verifies ownership row by row against Postgres before anything is returned.
Cross-tenant tests (two users, identical data) assert zero leakage through search, candidates, and graph paths.

## Failure modes and degraded behavior

- Extraction provider down: capture unaffected; raw retrieval works; jobs retry with backoff then park as `dead`, visible in `get_processing_status`.
- Embedding provider down: lexical and structured retrieval unaffected; `search_network` reports `vector` absent from contributing strategies and sets a coverage warning.
- Runtime API down: service falls back to direct SQL lexical retrieval (same tsvector column) and reports the degradation; vector and fuzzy strategies are skipped, never silently faked.
- Graph stale or unbuilt: relationship path falls back to relational claim lookup (same data, SQL join) with a coverage warning.
- Postgres down: the operation fails with a structured error and request id; there is no partial success to misreport.

## Rollout and rollback

Flags (environment, read by the service): `HAVEN_KNOWLEDGE_V0_ENABLED` (default off), `HAVEN_KNOWLEDGE_WRITE_MODE` and `HAVEN_KNOWLEDGE_SEARCH_MODE` (`off|shadow|primary`, default off).
Development and tests run `primary`; production stays `off`; nothing in the deployed app reads these flags yet, so no production traffic can switch by accident.
Rollback: flags off, stop the worker, optionally drop schema `haven_knowledge`; Convex is untouched by design.

## Test plan

Unit (no network, no database): hashing, offset validation, predicate validation, extraction-output validation, dedup, qualifiers, provisional creation rules, candidate suppression, RRF, deterministic rendering, owner resolution, redaction.
Database integration (managed Polygres, isolated per-run rows): transactional capture + outbox atomicity, idempotent retries, revision supersession, deletion cascade, FK integrity, concurrent job claiming, cross-tenant isolation, resolution preservation.
Polygres integration (Runtime API): readiness, text and fuzzy and vector retrieval, fusion, graph relation queries, insert-to-visible freshness, behavior after revision and deletion, structured errors, vector-unavailable fallback.
Retrieval evaluation: versioned fixture set with queries, expected people, expected evidence, and forbidden assertions; reports recall@5, MRR, evidence correctness, unsupported assertions, tenant leakage, deleted-content hits, and latency percentiles.

## Acceptance criteria

The 24 criteria from the task brief, verified in docs/evaluations/memory-knowledge-v0.md and the final report; each maps to at least one automated test or recorded command output.

## Open questions explicitly deferred

Question 7 (memory representation UI); global-scope capture; the deterministic-identity import path for automatic resolution; person summaries (item kind reserved); moving the service into a deployed runtime (Vercel Python function or a future Convex bridge); production Clerk JWKS verification wiring in whatever transport eventually fronts the service.
