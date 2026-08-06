# Polygres development validation, 2026-08-06

Everything below was executed against the real environment on this date; nothing is inferred from documentation alone.

## Versions and identity

- CLI: `polygres 0.2.0` (pipx; verified locally on 2026-08-06 before applying migration 0005).
- SDK: `polygres-sdk 0.1.0` (Python; the only documented Runtime API contract).
- Skills: the four `polygres-*` skills in `.claude/skills/` are byte-identical to `github.com/Evokoa/polygres-skills` HEAD (verified by diff).
- Authenticated as the project owner; organization Robotic Heron.

## Project

- `pa6ee1830f10557dcc9bfd0c` ("Haven"), status ready, effective tier `tier_nano`.
- Server: PostgreSQL 17.10; extensions installed: `vector`, `graph` (pgGraph), `pg_trgm`, `plpgsql`; also available: `pgcrypto`, `uuid-ossp`.
- Runtime API: `https://pa6ee1830f10557dcc9bfd0c.api.db.polygres.com/v1`, ready.
- Pre-existing content preserved untouched: 7 applied migrations (network mirror in `public`, generated tsvector columns, iMessage graph tables, probe, two im-sync truncates), configs `people_embedding`, `memories_embedding`, `people_search`, `memories_text`, `im_node_names`, and the graph registration of the 8 public tables.

## Authentication model (tested)

- The pooled and direct Postgres endpoints require password authentication: passwordless connect fails with `fe_sendauth: no password supplied`.
- The Runtime API key is NOT a database password: pooled rejects it with `FATAL: SASL authentication failed`, direct with `FATAL: password authentication failed` (tested 2026-08-06).
- The user-supplied connection string works after stripping the Prisma-only `?pgbouncer=true` query flag, which libpq rejects (`invalid URI query parameter: "pgbouncer"`). Both pooled and direct then authenticate.
- `polygres db psql` remains interactive-password only; `migrations apply` and `import csv` are the CLI's server-side write paths and need no database password.

## Runtime API surface (enumerated live)

- project: `readiness`, `connection_info`, `project_id`, plus namespaces.
- graph: `connection`, `expand`, `neighborhood`, `path`, `related`.
- vector: `search`, `similar_to`.
- text: `tsvector`, `fuzzy`.
- hybrid: `graph_first`, `vector_first`, `joint` (graph+vector only; there is no text-plus-vector endpoint, so lexical/vector fusion happens in Haven).
- `readiness()` reports vector `ready: true` (default config `people_embedding`, count includes `haven_retrieval_embedding`) and graph `ready` at the configuration level; `readiness.text` is not reported by the SDK object (check `text configs list` instead), matching the CLI reference note.

## Retrieval configuration findings

- Text configs on a schema-qualified table work (`--schema haven_knowledge`).
- The `--language` flag on `create-tsvector` governs QUERY parsing, and defaults to english. A config whose indexed column was generated with `to_tsvector('simple', ...)` but whose language stayed english matches nothing for morphologically variant terms: query `marathons` was stemmed to `marathon` and missed the stored token `marathons` (observed; `Sarah` still matched because names do not stem). Recreating the config with `--language simple` fixed it. Always pair the column's generation parser with the config's language.
- The runtime tsvector query builder has AND semantics; a literal `"a OR b"` query string is not honored. The application's lexical layer therefore retries zero-hit queries as one runtime query per meaningful term, merged with RRF client-side.
- Fuzzy over `haven_knowledge.knowledge_entities.normalized_name` works, one-transposition typos match ("lihn pham" finds "linh pham"); heavier corruption ("lin fam") legitimately misses at the default similarity threshold.
- Vector config `haven_retrieval_embedding` (1024 dims, cosine, hnsw) reports `index_status ready` on an empty column. Ready-at-config is not evidence of retrieval quality; the roundtrip test remains credential-gated (see below).

## Freshness (tested)

- TSVector: a row inserted through the application pipeline is retrievable through the Runtime API immediately (observed well under the 10s test ceiling; effectively first query). No rebuild, no external sync: the generated column and GIN index update in the insert transaction.
- Revision/deletion: superseded and deleted rows disappear from Runtime API results immediately via the `lifecycle_status` filter; verified by integration test.
- Graph: NOT fresh and NOT functional at the data-plane level, see below.

## Graph data plane: platform defect (observed, not inferred)

- `polygres ready`, `graph status`, and `graph build` all report "ready".
- `graph._projection_generations` is EMPTY and `graph._build_jobs` holds only `queued` rows, the oldest from 2026-07-31 -- the projection has never been built, for the pre-existing public graph as well as the new registrations.
- Every data-plane call fails with `PolygresAPIError: Data-plane query failed`, including a control query against the pre-existing `im_nodes` registration, so this is not caused by the haven_knowledge additions.
- A fresh `graph build` plus 20 minutes of polling produced no projection generation.
- Conclusion: on this project/tier the graph build queue is not being processed platform-side. "Ready" reflects saved configuration only. The application treats graph as a degraded strategy and answers relationship queries from relational claims (same data, SQL), with a coverage warning.

## Config registry after this work

Text: `haven_retrieval_text` (tsvector, simple, filters owner_id/lifecycle_status/primary_entity_id/item_kind), `haven_retrieval_text_english` (tsvector, english twin for the recorded parser comparison), `haven_entity_name_fuzzy` (fuzzy over normalized_name, filters owner_id/entity_state/entity_type).
Vector: `haven_retrieval_embedding` (retrieval_items.embedding, 1024, cosine, hnsw, filters owner_id/lifecycle_status/primary_entity_id/item_kind).
Graph: `knowledge_entities` (nodes, tenant owner_id) and `entity_relations` (edges via subject/object FKs) merged into the existing registration; `haven_users`, `auth_identities`, outbox, and claim tables are deliberately not registered.

## Limits

tier_nano; no explicit storage/row limits surfaced by the CLI for this tier during validation. Resource pressure reported healthy/unknown with no restriction active.
