# Review of graph/PLAN.md, second pass

Date: 2026-07-31.
Scope: the rewritten PLAN.md of 2026-07-31 01:11, plus graph/GOAL.md and graph/JOURNAL.md of 01:12.
This supersedes the first review, which targeted the previous version of the plan.

## Resolution, 2026-07-31

Every finding below, including the small items and the mentions deferral, was applied to PLAN.md and GOAL.md later the same day, over two revision rounds with a verifying review after each.
The 1,190-versus-1,047 discrepancy was resolved by measurement, not wording: 143 one-to-one chat rows are empty (drafts and cleared conversations), so 1,047 is the denominator.
The GOAL.md edits (constraints 1, 2, and 4, and the P2 list) were made under direct owner authorization, which the file's own no-edit rule anticipates.
This file stays as the record of why each change exists.
Do not re-apply anything below; the current PLAN.md and GOAL.md are the source of truth.

The rewrite resolved most of the first review's findings: the group bar now has a measured value, the Contacts halo is explicitly killed with numbers, the charter conflict is resolved by graph/ having its own GOAL.md, and the stale permission question is gone.
The measured-reality section is the strongest part of either version: the design now argues from 110,096 real messages instead of estimates, and the pruning target (1.19 edges per node against a 1.04 reference) is calibrated rather than guessed.

What follows is what the rewrite did not catch, ordered by how much it threatens the payoff.

---

## 1. The user's own node is unspecified, and it is the largest object in the graph

The plan never says what happens to the user.

Roughly 300 of the 820 projected edges are one-to-one edges, and every single one of them terminates at the user.
Add the user's membership in all 74 live groups and on the order of 380 of 820 edges, close to half the graph, converge on one point.

Three consequences follow, all bad:

- Node size scales with connection count, so the user renders as a planet.
- The force simulation gives every one of those ~380 edges a spring pulling toward one node, which compresses exactly the cluster separation the assembly animation exists to show.
  The plan's claim that clustering "falls out of the bipartite structure" is only true if the ego's springs do not fight it.
- The 40-label budget is partly spent on a node the user does not need labeled.

The standard answer from ego-network visualization applies: the ego is drawn but its edges are excluded from the simulation (or given near-zero weight), and ego edges render on focus rather than at rest.
The plan's own interaction section already contains the right home for this: "click a node to focus it, highlight its neighborhood."
Question 1, "who connects to me," is answered by presence and by focus mode, not by 380 permanent lines.

One sentence in the Visual section decides this.
It should be decided on paper, because it changes what the first render looks like more than any other open item.

## 2. Pipeline ordering bug: the filter runs before Contacts attaches

Pipeline step 4 filters non-people; step 5 attaches names from Contacts.
The never-replied rule removes 589 threads before any of them have names.

Some of those 589 are saved contacts: the parent whose texts get answered by phone call, the landlord, the FYI-only friend.
The plan names this exact failure at the dentist line and then leaves the collision unresolved.

The resolution is cheap and uses data the pipeline already loads:

- Swap steps 4 and 5.
- Add one rule: a handle that matches a Contacts card is never removed by the never-replied filter.
  Saved-but-noisy entries (a saved cable company) get included, and the user hides them, which is the plan's stated posture for ambiguity anyway.

This also fixes the build process, not just the runtime: build-order step 2 tunes the filter "against real results," and that tuning is only legible if the kill list has names on it.
A list of 589 bare numbers cannot be eyeballed for false positives; a list containing a saved contact's name can.

## 3. GOAL.md's `immutable=1` suggestion silently loses the newest messages

GOAL.md hard constraint 1 says: use `?immutable=1` or the read-only flag.
These are not equivalent, and the first one is a trap.

`chat.db` runs in WAL mode, and Messages holds it open and writes continuously.
Recent messages live in `chat.db-wal` until a checkpoint folds them in.
`immutable=1` tells SQLite the file cannot change, so it skips the WAL entirely: the read misses the newest messages, precisely the data a resync exists to pick up, and it is undefined behavior against a live writer.

Correct approach: plain read-only open, no immutable flag, accept that a WAL reader participates via the `-shm` sidecar (fine under Full Disk Access), and retry on `SQLITE_BUSY`.
`immutable=1` is only valid on a frozen copy, which constraint 1 separately forbids making.

The parenthetical in constraint 1 should be corrected before extraction is built, because extraction will otherwise be built to match it.

## 4. The model pass sits at the wrong point in the runtime pipeline

Build order gets this right: render at step 5, model pass at step 7, "get there fast."
But the runtime pipeline still runs the model pass (step 6) before build, prune, and render (steps 7 to 9).
Once the model pass exists, every import and resync blocks the payoff moment on a few hundred model calls, which at local-model speeds is minutes of staring at nothing.

The fix is sequencing, not budget:

- Render from metadata immediately; unnamed handles show their number.
- The model pass runs after first render and refines labels in place as guesses arrive.
- Guesses are cached keyed by normalized identifier, so a resync only queries handles never seen before, which is near zero.

This also downgrades the model-quality risk from "import feels broken" to "some labels stay numeric until a better guess lands."

Two related notes:

- Make the local provider (Ollama) the default and cloud an explicit opt-in.
  GOAL.md constraint 4 carves out "nothing is uploaded except the model pass"; a local default narrows that exception to a deliberate choice instead of a silent one.
- The plan already says to measure how many of the 615 lack a Contacts match before building this. Right call; that number sizes everything here.

## 5. Deriving group membership from activity deletes lurkers

The open-questions section resolves the `chat_handle_join` staleness problem by deriving membership from message activity, and calls it "correct either way."
It is not quite: a member who never posts vanishes.
Eight silent members of a 20-person group lose their group edge, and if the group was their only tie, their node.
For a friends graph, the lurker in the college thread still belongs to the college cluster.

Use both sources for what each is good at:

- Roster from `chat_handle_join`: complete, and even departed members are historically true, which fits a graph built from all history.
- Liveness and edge strength from activity, which the time filter needs per-message anyway.

The degenerate 2-member `style=43` chats the plan flags likely resolve the same way: if the roster is exactly the user plus one, render it as a one-to-one edge, not a group node.
Write the fixture for that case.

## 6. Resync discards curation unless the plan says otherwise

The interaction section gives the user real curation: hide nodes, remove intruders, answer the merge queue.
Resync is a full rebuild.
Nothing says the curation survives the rebuild, and by default it will not.

State the requirement in the plan so persistence (build step 8) is built to it:

- Overrides live in their own store, keyed by normalized identifier (E.164 or lowercased email), never by database row ids, which renumber.
- After every rebuild, overrides re-apply: hidden stays hidden, removed stays removed, answered merge questions are not re-asked.

## Small items

- Pruning needs one guard: never prune a node's last edge, or the prune cascades into hiding the node.
  With density already at 1.19 against a 1.04 target before mentions, pruning has little headroom anyway.
- The stack is now specified nowhere.
  The old plan said Swift and SwiftUI with reasons; the rewrite dropped the section, while GOAL.md assumes a Swift test target and the journal intends an Xcode scaffold.
  One line in PLAN.md naming the stack ends the drift.
- Two counts disagree: measured reality says 1,190 one-to-one chats, the reciprocity paragraph says 1,047 one-to-one conversations.
  Probably chat rows versus deduped counterparties; define the denominator once, because the 56% claim inherits it.
- `docs/loop/GOAL.md` is the old Haven-import charter and still sits in the repo unmarked.
  Add a dormant notice at its top so no future loop reads the wrong charter.

## Owner decision not yet folded in: mention edges

In a parallel session on 2026-07-31, the owner chose to defer mention edges rather than keep them.
PLAN.md still carries them as a core edge type, the pipeline still extracts them, and GOAL.md P2 step 7 still names them.

The measured data independently supports deferring:

- Density already sits at 1.19 edges per node against the 1.04 reference before a single mention edge lands; mentions push the render away from its own calibration target.
- Resolving a first name in message text to one node among 615 people is guesswork, and a mention ("ran into Mike") is weak evidence of a relationship even when resolved correctly.
- Deferring shrinks the model pass to unnamed-handle labeling only: a few hundred snippets once, instead of scanning all one-to-one text for names.

If the decision stands, the edits are: move mentions to Deferred, drop extraction from pipeline step 6, drop "and mentions" from GOAL.md P2 step 7, and note that the 820-edge projection is then the whole graph rather than a floor.

## What the rewrite got right, for the record

- Measuring before designing, and stating facts as facts.
- The bipartite argument now carries a measured example: one 32-person chat alone would fabricate 496 friendships.
- Contacts demoted to a naming layer, with the 7,700-isolated-dots argument made explicit.
- The two-day group bar chosen from the measured 74/38 split, with the toggle preserving the ability to tighten later.
- The personal-tool reframe, which deletes distribution, notarization, onboarding funnel, and export-consent concerns in one honest move.
- GOAL.md constraint 3: no real personal data in git, with the gitignore ordered before the first data-touching commit.
- The tune-against-real, assert-against-fixtures split, with the fixture shapes already listed.
- Build order fronting the first visible payoff.
