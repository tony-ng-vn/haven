# Haven Knowledge Service (v0)

The evidence-preserving knowledge foundation behind Haven memories: raw source entries, immutable versions, extracted claims with exact evidence, provisional references, concepts, and hybrid retrieval, stored in the Polygres project's `haven_knowledge` schema.
Spec: `docs/specs/haven-memory-knowledge-foundation-v0.md`.
Nothing in the deployed app calls this yet; it ships behind flags, off by default.

## Setup

```sh
cd knowledge
python3 -m venv .venv
./.venv/bin/pip install -e '.[dev]'
```

Environment (in the repo-root `.env.local`, gitignored; see `.env.local.example` for the Polygres section):

- `DATABASE_URL`, `DIRECT_URL`: credentialed Postgres URLs (strip any `?pgbouncer=true`; libpq rejects it).
- `POLYGRES_RUNTIME_URL`, `POLYGRES_API_KEY`: Runtime API.
- `EXTRACTION_BASE_URL`, `EXTRACTION_API_KEY`, `EXTRACTION_MODEL`: extraction provider (or a valid `OPENAI_API_KEY`).
- `VOYAGE_API_KEY`: embeddings (voyage-3.5, 1024 dims); falls back to `OPENAI_API_KEY` (text-embedding-3-small shortened to 1024).
- Flags: `HAVEN_KNOWLEDGE_V0_ENABLED=1`, `HAVEN_KNOWLEDGE_WRITE_MODE=primary`, `HAVEN_KNOWLEDGE_SEARCH_MODE=primary` for development; everything defaults to off.

Migrations are applied server-side: `polygres --project pa6ee1830f10557dcc9bfd0c migrations apply --file knowledge/migrations/<file>.sql`.

## The developer vertical slice

`scripts/knowledge/kcli.sh` wraps the CLI with `.env.local` sourced and dev flags on. The whole v0 loop:

```sh
# 1. Mirror a canonical person (the Convex id is an opaque external mapping).
scripts/knowledge/kcli.sh mirror-person --convex-id demo_sarah --name "Sarah Tran"

# 2. Capture a raw person-anchored memory (immediately text-searchable).
scripts/knowledge/kcli.sh add --convex-id demo_sarah \
    --text "Met Sarah through Alex at YC Demo Day. She runs marathons."

# 3. Run the background pipeline (extraction, embeddings).
scripts/knowledge/kcli.sh worker --drain

# 4. Inspect what became of it.
scripts/knowledge/kcli.sh status <entry-id>
scripts/knowledge/kcli.sh person <entity-id>

# 5. Search, including the qualified unresolved-reference answer.
scripts/knowledge/kcli.sh search "endurance sport"
scripts/knowledge/kcli.sh search "who introduced me to Sarah?"

# 6. Reference resolution (deliberate, never by name similarity).
scripts/knowledge/kcli.sh candidates <provisional-id>
scripts/knowledge/kcli.sh resolve <provisional-id> <candidate-id>

# 7. Revise and delete; derived data follows in the same transaction.
scripts/knowledge/kcli.sh revise <entry-id> --text "Sarah moved to New York."
scripts/knowledge/kcli.sh delete <entry-id>
```

The dev identity is `HAVEN_DEV_IDENTITY` ("issuer|subject"), defaulting to a synthetic development identity; owner ids are always resolved server-side and never accepted as input.

## Tests and evaluation

```sh
scripts/knowledge/pytest.sh tests/unit          # pure logic, no network
scripts/knowledge/pytest.sh tests/integration   # managed DB + Runtime API; skips visibly without credentials
scripts/knowledge/eval.sh                       # repeatable retrieval evaluation, prints JSON
```

Results and methodology: `docs/evaluations/memory-knowledge-v0.md`.
Platform findings (auth model, freshness, the stuck graph build queue): `docs/polygres/development-validation.md`.
