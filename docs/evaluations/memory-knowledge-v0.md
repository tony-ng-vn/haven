# Retrieval evaluation: memory knowledge v0

Eval set version: `memory-knowledge-eval-v1` (knowledge/eval/fixtures.py).
Harness: `knowledge/eval/run_eval.py`, run via `scripts/knowledge/eval.sh`.
The harness is fully repeatable: it creates a throwaway owner (plus a second owner for tenant isolation), pushes every fixture through the real pipeline, measures, asserts, prints one JSON report, and deletes everything it created.

## What the set contains

Six declarative scenarios (direct interest and need; provisional reference; conservative inference; modality; negation; history) with 11 queries, plus four procedural fixtures: multiple Alexes (candidates without auto-resolution), revision (San Francisco -> New York), deletion (antique compasses), and two-tenant isolation (identically named people).
Forbidden-assertion lists encode inference policy B: for "Sarah runs marathons", nothing persisted may contain disciplined, outdoorsy, health-conscious, hiking, exercises every day, or accountability partner.

## Results, 2026-08-06 (run 4, after fixes; extraction interfaze-beta; embeddings unavailable, lexical + structured only)

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

Latency (measured, development machine to managed tier_nano, per stage):

- raw source write: avg 1.9s, p95 2.6s (n=6)
- text-search availability after write: avg 3.7s, p95 4.7s (includes a full search_network call, not just the index)
- extraction per run (model call + validation + persist): avg 4.4s, p95 7.9s (n=10)
- standard query end to end: avg 3.5s, p95 4.3s (n=10; includes one failed embedding attempt per query while the credential is absent)
- relationship query: 1.4s (n=1)

These are development-latency observations dominated by model-provider and cross-continent round trips, not database time; the capture path never waits on extraction by design.

## Runs 1-3 and what they changed

- Runs 1-2 (recall 0.7): lexical-only misses on "marathon runner" and "endurance sport", and one relationship miss. Root causes found from the debug snapshot: the runtime's AND-shaped query parser ignored the literal "OR" retry; the model phrased activities through custom predicates, which skipped concept mapping; one junk boolean object.
- Run 3 (recall 0.8): per-term OR retry landed; provisional normalization for person-shaped text objects landed.
- Run 4 (recall 1.0): predicate-preference prompt hardening, concept mapping extended to custom-predicate objects, boolean-object guard.

## Honest limitations

- Vector retrieval contributed nothing yet: no valid embedding credential existed at evaluation time. The semantic-similarity claims of the design (paraphrase recall beyond taxonomy terms, "possible running partner"-style labeled inference) are UNMEASURED. Re-run this eval after setting VOYAGE_API_KEY; the harness picks it up automatically and reports `embeddings_available: true`.
- Extraction is nondeterministic run to run; the recorded numbers are single-run, not averaged. EVAL_RUNS-style repetition is a straightforward extension.
- Graph traversal was not exercised (platform build queue stuck); relationship answers were served relationally.
- The fixture set is small (by design for v0); treat recall@5 = 1.0 as "the machine works", not "retrieval is solved".
