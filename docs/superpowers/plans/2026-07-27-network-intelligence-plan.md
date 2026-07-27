# Network intelligence: memory-first search plan

The goal, in the owner's words from 2026-07-27: every single data point about a person in your network is searchable, the way human memory works.
"Do I know anyone with database experience" must surface the person from Founder Inc who works on an infinite-context-window database, whatever words the note used.
When the need is underspecified, the system asks a clarifying question instead of returning noise.
And when nobody matches directly, it makes the human move: nobody here is a founder, but this person works at a YC startup, so they can probably introduce you to one - suggested as a bridge, with the reasoning shown.

Those are three distinct capabilities, and this plan builds them in order: recall (wave A), then reasoning and dialogue (wave B), with the supply of memories (wave C) as the product loop that feeds both.
Spec authorities: `mvp-design.md` for the product frame, `docs/superpowers/plans/2026-07-26-capture-pipeline-plan.md` for capture; those win on conflict.

## Architecture stance

Read this before building anything; it is what keeps the plan cheap.

- A personal network is small: hundreds of people, not millions.
  The reasoning levels are therefore one LLM call over compact dossiers of the whole network, not graph infrastructure.
  Do not build a graph database, edge tables, or server-side chat sessions for this.
- Embedding retrieval is for instant type-ahead, and becomes the candidate selector only once dossiers outgrow a single call's budget.
  It is not where the intelligence lives.
- The ceiling on quality is the supply of memories, not the ranking function.
  A perfect search over empty context fields returns nothing.
- Standing rule, learned from the dropped-bio bug (PR 108): any new data point about a person lands in `personSearchText` and `buildEmbedText` in the same PR that adds it, or it is invisible to search and the point of this plan is defeated.

## State as of 2026-07-27

- Merged: keyword search plus company/city/role facets, one embedding per person behind a userId-filtered vector index, `semanticSearch` (top 8, cosine floor 0.3), the iOS Search screen wired to the directory backend (PR 105), extraction at low image detail (PR 104).
- In flight: PR 108 persists the extracted bio onto the person and into both haystacks.
- Known limits this plan removes: one vector per person averages all their memories, so a query hitting one facet of a well-known person scores low; results carry no evidence of why they matched; keyword and semantic are two endpoints the client must choose between; `context` is one newline-joined blob with no per-entry timestamps; memory capture is a single optional note at save time.

## Wave A: memory substrate (one session, serial, one PR)

Branch `feat/convex-memories`, after PR 108 merges.

1. A `memories` table: `userId`, `personId`, `text`, `createdAt`, optional `embedding` and `embeddedText`, with a userId-filtered vector index and a by_person index.
   Every write path that appends to `person.context` today (addPerson note, editPerson context change, saveSharedProfile note, capture accept context) also inserts a memory row in the same transaction.
   `person.context` stays as the rolled-up display copy; memories are the retrieval copy.
2. Per-memory embeddings through the same pattern as `people.embed`: scheduled, retried with backoff, idempotent on the stored embedded text.
3. Migration `people:backfillMemories`: split each person's existing context on newline into memory rows stamped with the person's `updatedAt`, cursor-paged and idempotent (a person who already has memory rows is skipped and counted).
   `appendContext` has always joined with a newline, so the split is faithful to entry boundaries.
4. `semanticSearch` v2: embed the query once, vector-search memories and people, aggregate per person by max score, and return evidence with each hit: the matching memory text (or the matched card field).
   Evidence is the trust feature; a memory-search result without "matched because you wrote ..." reads as random.
   Keep the response shape backward compatible until the iOS Search screen adopts evidence.

Exit criteria: full suite and both typechecks green, merged, migration run against the deployment that holds real people (`brilliant-puma-925`) and its counts reported.

## Wave B: the ask endpoint (one session, after wave A merges)

Branch `feat/convex-ask`.

1. `people.ask` action: build a compact dossier per person (name, headline, bio, role at company, city, platform names, memory lines with dates), cap total tokens, and if the network outgrows the cap, embed-retrieve the top K people first and dossier only those.
   Send to an LLM behind the same env-swappable provider pattern extraction uses (`ASK_BASE_URL` / `ASK_API_KEY` / `ASK_MODEL`, OpenAI fallback), with a strict json_schema output: `{ matches: [{ personId, kind: "direct" | "bridge", why }], clarifyingQuestion: string | null }`.
   Bridging is prompt-level, not infrastructure: instruct the model that when no direct match exists it should propose adjacency ("works at a YC startup, likely knows founders") as kind "bridge", never dressed up as a direct match, always with its reasoning in `why`.
   Rate-limit like `semanticSearch`, and measure real cost per ask before trusting defaults, the same way the extraction detail change was measured.
2. Conversational refinement: `ask` accepts prior turns as an argument; the client holds the history.
   Each call either answers or asks exactly one clarifying question; no server session state.
3. Evaluation, before any threshold tuning: a checked-in fixture set of (network dossier, query, expected personIds, expected kind) pairs, including bridge cases and Vietnamese-note-with-English-query cases, run by a script against the live model to report recall.
   CI keeps contract tests against a mocked provider; the live eval is a script because model output is not deterministic enough for CI.
   The 0.3 semantic floor was tuned once on early data; it gets recalibrated against this eval, not by feel.

## Wave C: the supply side (product decisions, with the user)

Nothing in waves A or B blocks on these, but this is where the goal is actually won or lost.

- The evening follow-up prompt (capture milestone 6, deliberately deferred from MVP) is the single highest-leverage feature for memory supply; decide whether to pull it forward once MVP ships.
- Voice note to memory row (capture-plan open question 3).
- Structured "where we met" and "who introduced us" at save time; both are exactly the cues memory queries use.
- Privacy: `ask` sends the whole network's dossiers to the LLM provider.
  Screenshots already go to the same providers, but the Phase 6 privacy labels must say so, and the provider choice is the user's call.

## Costs, measured where live on 2026-07-27

- Extraction: about $0.033 per capture at low detail (evidence table in PR 104).
- Ask: a 200-person network at roughly 120 tokens per dossier is about 24k prompt tokens - around $0.04 on interfaze-beta, under a cent on gpt-4o-mini; it is per-query, so the rate limit matters more than caching.
- Embeddings: text-embedding-3-small, negligible at this scale.

## Model guidance per session

- Wave A: Opus; the migration and the both-haystacks invariant are where mistakes corrupt retrieval quietly.
- Wave B1: Opus; B2 and B3: Sonnet.
- Wave C: interactive with the user; production credentials never go to a background agent.
