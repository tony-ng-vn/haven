# Loop journal

Newest entry first.
The loop reads this at every iteration start and appends at every iteration end.
See `graph/GOAL.md` for the rules. That file is user-owned; the loop never edits it.

Real measurements belong here. Real names and message content do not.

## Standing state

- Open PRs: #182 (graph/build -> graph-main), awaiting CI
- Build position: P2 step 4 (graph construction) implemented, pending merge; next is P2 step 5 (layout, render, assembly animation - first visible payoff, first SwiftUI app work)
- Integration branch: `graph-main`, created 2026-07-31 per owner directive; the loop merges its own PRs there after green CI and self-review, main stays untouched, user merges graph-main to main
- Journal discipline: the canonical charter and journal copies live in the main checkout at `graph/`; the loop mirrors them into the graph-main worktree and commits there, always editing the main-checkout copy first
- Blocked on user: Ollama, the plan's default local provider, not yet installed (needed only at P2 step 7)
- Next intent: merge #179 when CI is green, then start P2 step 2

## Entries

### 2026-07-31 iteration 4: graph construction (PR #182)

DONE

- #181 merged to graph-main after green CI and lead review; worktree and branch removed.
- GraphModel and GraphBuilder: user/person/group nodes; edges with canonical pair ids, source enum (imessage only today, call history rides in later), reason, strength (distinct active days), involvesUser flag for the renderer's ego-edge exclusion. Two-member style-43 chats become one-to-one edges; dead groups built and flagged isLive=false; lurker edges kept at strength 0; removed people produce nothing. Prune mechanism with the never-a-last-edge guard and full user-edge exemption, default threshold keeps everything. 52 tests (9 new), all red-first against a stub with captured failures; prune exemption additionally mutation-verified.
- Real-data graph, the goal's node and edge counts: 1 user + 574 people + 52 live groups + 42 dead groups = 669 nodes. Edges: 317 oneToOneThread, 532 groupMembership, 94 userGroupMembership, 943 total. Built in 2.3 seconds. The 130 raw groups split exactly as 94 nodes + 36 reclassified two-member chats. Plan projections hit within a few percent (projected ~300 one-to-one, 513 membership).
- Density bookkeeping: the plan's 1.19 edges/node (820/689) counted one-to-one plus membership edges over people plus live groups. The comparable measured figure is (317+532)/(574+52) = 1.36. The CLI's edgesPerNode prints 0.85 because it excludes ALL user-involving edges from the numerator (including the 317 one-to-one edges the plan counted); note for P3/P4: align that metric's definition with the plan's before using it for pruning decisions.
- Median person/group degree is 1: most people hang off the user alone (their one-to-one edge) rather than clustering through groups. The rendered rest state (user edges hidden) will show many isolated dots plus group clusters; worth watching at step 5, and the plan anticipates exactly this shape.
- Builder decisions worth remembering: group liveness counts messages from filtered-out senders too (a spam-heavy group can be live through traffic the person filter discarded); group nodes are built even when every member was filtered, leaving user-only satellite groups; both are deliberate and pinned by tests.

IN-FLIGHT

- PR #182 against graph-main, waiting on CI.

BLOCKED

- Ollama install (P2 step 7 only).
- Liveness-bar refinement decision from iteration 3.

NEXT

- Merge #182 on green. Then P2 step 5: layout, render, assembly animation - the SwiftUI app target, force simulation, and the first moment this is worth looking at.

### 2026-07-31 iteration 3: non-person filter (PR #181)

DONE

- #180 merged to graph-main after green CI and lead review; worktree and branch removed.
- PersonFilter implementing the plan's rules in the plan's order: shortcode, alphanumeric sender (emails structurally exempt), never-replied per person across combined one-to-one threads, then the separate node-eligibility bar notLive (2+ distinct calendar days, injected calendar so tests pin UTC). Card and group-with-humans overrides outrank rules 1-3 only. Two-member style-43 chats count as one-to-one everywhere. CLI gains `filter` (counts) and `killlist` (reason, name or masked id, activity facts; on-screen review only, never committed). 43 tests total, 14 new, all red-first against a stub; one test proven load-bearing by mutation.
- Real-data run: kept 574 (135 carded, 439 uncarded), removed 1,336: shortcode 201, alphanumeric 46, neverReplied 422, notLive 667. Full pass about 2 seconds. Kept 574 sits close to the plan's 615 projection.
- Kill-list review with names attached, done on screen; aggregates only here:
  - The card override provably works: zero carded people were removed by rules 1-3. All 22 carded removals came from the liveness bar.
  - The liveness bar is the one rule that bites real people: among its removals are heavy single-day mutual conversations (up to 56 messages with 25 replies from the user) and 130 uncarded replied-but-single-day threads. These look like met-once real contacts (events, trips).
  - Automated buckets look correct: heaviest shortcode shows 520 messages across 316 distinct days (the OTP signature); alphanumeric senders are all business codes. One curiosity: one shortcode carries 25 user replies over 2 days, an interactive SMS service, removed per rule, acceptable.
  - 3-digit sender codes fall outside the 4-6 digit shortcode rule but are caught by neverReplied or notLive anyway.
  - Masking degenerates for identifiers of 5 or fewer characters (shortcodes and sender ids print nearly whole); accepted, those are broadcast business codes, and personal numbers always mask to last-4.
- Suggestion for the user (PLAN refinement, not acted on): let a reply from you (fromMe > 0), or card-plus-reply, satisfy one-to-one liveness. It would move up to roughly 150 replied-to single-day people into the graph (574 to about 720), including the 22 named ones. The plan's two-day bar is explicit, so this stays blocked on your decision; the density calibration (1.19 edges per node) would need rechecking if adopted.
- Perf note for P4: the filter does a full message scan per person (about 200M iterations); fine at 2 seconds, worth pre-grouping if it ever grows.

IN-FLIGHT

- PR #181 against graph-main, waiting on CI.

BLOCKED

- Ollama install (P2 step 7 only).
- Liveness-bar refinement decision above.

NEXT

- Merge #181 on green. Then P2 step 4: graph construction (nodes, edges, pruning), where the 574 people plus live groups become the actual node and edge lists.

### 2026-07-31 iteration 2: identity resolution (PR #180)

DONE

- #179 merged to graph-main after green CI (all five checks) and lead review; worktree and branch removed. Vercel builds a preview per PR branch automatically; that is a preview only, production builds come from main, which this loop never touches.
- Handle normalization (.email lowercased / .phone E.164 with US default / .other untouched), identity resolution via union-find with exactly the plan's two auto-merge rules, names and thumbnail photos attached from cards (ZTHUMBNAILIMAGEDATA blob, measured present on 102 of ~209 cards in the main source db), merge-candidate queue for same-name-no-evidence pairs. CLI `people` subcommand, counts only. Strict red-then-green throughout, with the failing assertion captured per behavior.
- A first-draft determinism test was caught being vacuous (passed even with sorting removed, proven across 5 process runs); rewritten to pin expected output, mutation now kills it.
- Real-data crash found and fixed: contact cards were keyed on Z_PK, but the real store is three databases with colliding Z_PK spaces. Reproduced from a two-database fixture (process crash as the red state), then keyed cards on ZUNIQUEID, measured non-null and distinct across all three real databases (3 + 209 + 38 = 250 cards). NULL ZUNIQUEID rows are skipped. Chosen posture: a duplicate ZUNIQUEID traps loudly rather than silently dropping a card; today's data has no cross-database duplicates.
- Real-data run: 1,910 people from 1,918 raw identifiers (normalization plus card unions net -8). 157 people carry a contact card, 71 a photo, 11 hold multiple identifiers (10 with two, 1 with three), merge queue holds exactly 2 pairs. So of 250 cards, 93 match nobody who appears in Messages.
- Model-pass sizing sharpened: if roughly 615 people survive the step 3 filter, at most 157 arrive named; roughly 450+ will need the model pass or stay number-labeled. The plan's open question 2 now has a measured ceiling.

IN-FLIGHT

- PR #180 against graph-main, waiting on CI.

BLOCKED

- Ollama install (P2 step 7 only).

NEXT

- Merge #180 on green. Then P2 step 3: the non-person filter, tuned against real results with names attached to the kill list for review.

### 2026-07-31 iteration 1: extraction (PR #179)

DONE

- Created the `graph-main` integration branch and the `.worktrees/graph-extraction` worktree; committed charter docs plus `graph/.gitignore` before any code.
- Swift package under `graph/`: GraphCore library, graph-cli executable, 19 tests, zero dependencies. chat.db opened SQLITE_OPEN_READONLY (no immutable flag, busy timeout plus bounded retry); every SELECT names columns; message.text and attributedBody never referenced; a reflection test with a positive control proves no message text reaches the model; a byte-comparison test proves extraction does not modify the database file.
- Review found the never-replied test was mutation-blind (symmetric fixture: 1 never-replied vs 1 replied, so an inverted predicate produced the same count). Strengthened to 2-vs-1; the mutant now fails the suite.
- Real-data run, numbers only: joined messages 108,463 plus 1,634 unjoined equals 110,097, matching the profiled 110,096 plus one new message. Handles 2,160 over 1,918 distinct identifiers. Chats 1,320 (1,190 one-to-one, 130 group). One-to-one with messages 1,047, empty 143, never-replied 589. Two-member style-43 chats: 36. Group sizes 2 to 32; the 18-20 bucket holds 21 groups; singles at 26, 28, 31, 32. Services SMS 1,163 / iMessage 655 / RCS 342. All charter calibration numbers reproduced.
- Shortcode count is 201 under the 4-to-6-digit rule vs the charter's 213 under "fails phone parsing"; definitional difference, to be settled when the non-person filter is built (P2 step 3).
- Major calibration correction: PLAN.md's "8,342 Contacts records" counted every ZABCDRECORD row; 8,138 of those are ABCDInfo bookkeeping entities. The real address book holds 250 contact cards (237 with a phone, 13 with an email). The reader initially excluded the bookkeeping rows only by accident of their NULL fields; fixed the same day, strict red-then-green, to filter by the ABCDContact entity via Z_PRIMARYKEY lookup and to throw on unrecognized schema.
- Consequences of that correction, for the user to fold into PLAN.md if agreed: (1) open question 2 is answered in direction: at most ~250 of the ~615 graph people can carry a Contacts name, so the model pass covers the majority of nodes rather than a tail; (2) merge evidence from cards co-listing phone and email is nearly absent (13 cards with any email), so auto-merge will be dominated by exact-identifier equality and the merge queue should be small; (3) the Contacts-card spare rule in the never-replied filter protects at most ~250 handles.
- Process note: the initial scaffold deviated from TDD (tests written after implementation), mitigated by mutation-testing the two riskiest assertions plus the lead spot-check that exposed the weak never-replied test. The follow-up contacts fix was done strictly red-then-green. Future build steps carry the strict ordering requirement in the brief from the start.

IN-FLIGHT

- PR #179 open against graph-main, waiting on CI (the repo's `test` workflow runs npm tests on the self-hosted mac; graph changes do not touch that surface).

BLOCKED

- Ollama install (P2 step 7 only).

NEXT

- Merge #179 on green CI. Then P2 step 2: identity resolution plus names and photos from Contacts.

### 2026-07-31 design revision, second pass

Plan revised per the second-pass review.
The user's own node is drawn but its edges are excluded from the force simulation and the rest-state render; ego edges surface only on focus.
Contacts attach moved before non-person filtering, with a new rule that a Contacts-card match is never removed by the never-replied filter.
GOAL.md's `?immutable=1` guidance was wrong and is corrected to a plain read-only open that participates in the WAL via the `-shm` sidecar and retries on SQLITE_BUSY.
The model pass now runs after first render, asynchronously, with guesses cached by normalized identifier and Ollama as the local default; cloud is opt-in.
Group roster comes from `chat_handle_join`, with liveness and edge strength from message activity, so lurkers keep their edge.
Two-member `style=43` chats resolve to a one-to-one edge, not a group node.
Resync curation (hidden nodes, removed nodes, answered merges) now survives rebuild through a separate overrides store keyed by normalized identifier.
Mentions are deferred by owner decision.
Stack is stated as Swift and SwiftUI.
The reciprocity denominator is fixed: 1,047 of the 1,190 one-to-one chat rows contain messages, the other 143 are empty.

No code written yet.

### 2026-07-31 setup

Design settled through a grilling session. `PLAN.md` written and calibrated against the real database.

Measured, metadata only, no content read: 110,096 messages spanning 2022-10-21 to 2026-07-31, 177MB. 2,160 handle rows over 1,918 distinct identifiers. 1,320 chats, of which 1,190 one-to-one and 130 group. Service mix SMS 1,163 / iMessage 655 / RCS 342. 213 shortcode handles. 8,342 Contacts records.

Key calibration: of 1,047 one-to-one conversations, 589 contain no reply from the user, so the reciprocity rule alone removes 56% of noise. Group sizes are bimodal, 81 groups at 5 or fewer members and 21 in the 18-20 range plus singles at 26, 28, 31, 32.

Projected graph under the plan's rules: 615 people plus 74 live group nodes, 820 edges before mentions, giving 1.19 edges per node against 1.04 in the reference image.

No code written yet.
