# ADR: Haven Knowledge Service boundary

Date: 2026-08-06.
Status: accepted.

## Decision

The knowledge domain is implemented as a small server-side Python package, `knowledge/`, that owns all Polygres access: psycopg for transactional writes, the official `polygres-sdk` (0.1.0) for retrieval, and direct provider HTTP for extraction and embeddings.
For v0 it runs as a library plus a developer CLI harness and worker process; it is not deployed anywhere.
The existing Convex backend, web app, and iOS app are untouched.

## Alternatives considered

### Option 1: Convex Node actions holding pg connections

Rejected on three verified grounds.

1. Credential model.
   The Polygres Postgres endpoints require password authentication (verified: `fe_sendauth: no password supplied` without one, `FATAL: password authentication failed` and `FATAL: SASL authentication failed` with the Runtime API key on the direct and pooled endpoints respectively, 2026-08-06).
   The public documentation example observed at the start of the spike used CLI 0.1.2 and provisioned no database password; no password existed in any local or deployment environment that day.
   A Convex action would have nothing to authenticate with.
2. Retrieval SDK language.
   The only documented Runtime API contract is the Python `polygres-sdk`; its raw HTTP surface is not documented, and both the CLI and SDK skills forbid inferring undocumented payloads.
   A TypeScript Convex action would have to reverse-engineer the REST protocol to retrieve, which is out of bounds.
3. Deployment safety.
   Testing inside the Convex runtime requires deploying spike code to the shared dev deployment (`brilliant-puma-925`), which currently serves the user's live in-flight branch work.
   Deploying from this worktree would overwrite those deployed functions, which is exactly the kind of unrelated-work clobbering this task forbids.

Because of (3), no connectivity test was run inside the Convex runtime.
The decision does not rest on that untested capability: grounds (1) and (2) are each independently sufficient and were tested directly from this machine.

### Option 2: Minimal knowledge service (chosen)

Python was chosen over TypeScript because retrieval is only reachable through the Python SDK, and splitting the domain across two languages (TS writes, Python reads) would duplicate the domain model on both sides of an internal boundary.
The repository already carries Python for the graph research tool and `scripts/generate-brand-assets.py`, so a second toolchain is precedent, not novelty.

## The connectivity spike

What was actually executed and observed (all on 2026-08-06, recorded in docs/polygres/development-validation.md):

- `polygres` CLI 0.2.0 authenticated as the project owner; project `pa6ee1830f10557dcc9bfd0c` status ready.
- Runtime API reachable and authenticated with the new `haven-knowledge-dev` key; readiness reports graph and vector ready; SDK namespaces graph/vector/text/hybrid enumerated.
- Postgres endpoints reject passwordless and API-key auth (see above); server-side `migrations apply` and `import csv` are the write paths available without the database password.
- Local fallback for transactional integration tests: Dockerized `pgvector/pgvector:pg17`, schema-identical to the managed database.

## Operational consequences

- Interactive traffic uses the pooled endpoint; migrations use the CLI's server-side migration runner (and the direct endpoint if a password is provided).
- The worker is a separate process with its own connection and concurrency limits, so background extraction cannot starve interactive retrieval.
- Secrets live in the gitignored `.env.local` only: `POLYGRES_API_KEY`, optional `PGPASSWORD`, provider keys.
  Nothing is VITE_-prefixed, so nothing can reach a client bundle.

## Deployment consequences

The service is deliberately deployable in three shapes without code change: a long-lived process (worker + HTTP), a Vercel Python function (Fluid Compute supports Python and holds pooled pg connections per instance), or invocation from a future Convex Node action through an HTTP boundary once one exists.
Choosing between them is out of scope for v0 and does not affect the domain interface.
Before a long-lived worker or HTTP deployment, choose workload-specific database connection and statement timeouts and either add reconnect backoff or place the worker under a process supervisor.
The current developer drain command intentionally exits when its database connection is lost.

## Rollback path

Delete or ignore the `knowledge/` package and stop the worker.
No other component imports it.
The `haven_knowledge` schema can be dropped independently of the `public` mirror and iMessage tables.
