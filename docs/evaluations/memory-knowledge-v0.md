# Retrieval evaluation: memory knowledge v0

Eval set version: `memory-knowledge-eval-v1` (knowledge/eval/fixtures.py).
Harness: `knowledge/eval/run_eval.py`, run via `scripts/knowledge/eval.sh`.
The harness is fully repeatable: it creates a throwaway owner (plus a second owner for tenant isolation), pushes every fixture through the real pipeline, measures, asserts, prints one JSON report, and deletes everything it created.

## What the set contains

Six declarative scenarios (direct interest and need; provisional reference; conservative inference; modality; negation; history) with 11 queries, plus four procedural fixtures: multiple Alexes (candidates without auto-resolution), revision (San Francisco -> New York), deletion (antique compasses), and two-tenant isolation (identically named people).
Forbidden-assertion lists encode inference policy B: for "Sarah runs marathons", nothing persisted may contain disciplined, outdoorsy, health-conscious, hiking, exercises every day, or accountability partner.

## Results, 2026-08-06 (run 5; extraction interfaze-beta; Voyage embeddings enabled)

- recall@5: 1.0 (11/11)
- MRR: 0.95
- evidence correctness: 1.0 (every hit carried an exact quote from its source)
- unsupported assertions persisted: 0
- tenant leakage: 0
- deleted-content retrieval hits: 0
- negation never satisfied a positive query: true
- modality preserved on uncertain claims: true
- temporal status preserved on historical claims: true
- multiple Alexes: unresolved, both candidates listed, none auto-selected: true
- revision: old city invisible, new city visible: true
- extraction runs: 10/10 succeeded
- active retrieval items embedded: 22/22
- vector contribution: 10/10 standard queries

Latency (measured, development machine to managed tier_nano, per stage):

- raw source write: avg 0.96s, p95 1.27s (n=6)
- full hybrid search used for the text-availability probe: avg 22.38s, p95 42.51s (n=6)
- extraction per run (model call + validation + persist): avg 3.31s, p95 5.62s (n=10)
- embedding drain wall clock: 488.06s for the initial fixture set
- standard hybrid query end to end: avg 28.16s, p95 67.60s (n=10)
- relationship query: 1.76s (n=1)

The unbilled Voyage account used for this run allows three requests per minute.
The harness deliberately waits through that quota so it can verify the complete vector path, which produces the roughly 67-second tail every fourth embedding request.
The text-availability probe calls the full hybrid search, so its number includes the same embedding wait and is not a measurement of the tsvector index alone.
Interactive product queries fail fast on an embedding 429 and continue with lexical and structured retrieval instead.
These are development observations, not production latency targets, and the capture path never waits on extraction by design.

## Runs 1-5 and what they changed

- Runs 1-2 (recall 0.7): lexical-only misses on "marathon runner" and "endurance sport", and one relationship miss. Root causes found from the debug snapshot: the runtime's AND-shaped query parser ignored the literal "OR" retry; the model phrased activities through custom predicates, which skipped concept mapping; one junk boolean object.
- Run 3 (recall 0.8): per-term OR retry landed; provisional normalization for person-shaped text objects landed.
- Run 4 (recall 1.0): predicate-preference prompt hardening, concept mapping extended to custom-predicate objects, boolean-object guard.
- Run 5 (recall 1.0): the real Voyage vector path ran to completion; the acceptance gate now requires every active item to be embedded, at least one vector-contributing query, correct revision evidence, owner-scoped workers, and evidence-based tenant and negation checks.

## Honest limitations

- Voyage's unbilled three-RPM quota makes this harness slow and is unsuitable for concurrent production workers.
- Retry timing is currently per call, not coordinated across worker processes, and does not honor provider `Retry-After` yet.
- Extraction is nondeterministic run to run; the recorded numbers are single-run, not averaged. EVAL_RUNS-style repetition is a straightforward extension.
- Graph traversal was not exercised (platform build queue stuck); relationship answers were served relationally.
- The fixture set is small (by design for v0); treat recall@5 = 1.0 as "the machine works", not "retrieval is solved".
