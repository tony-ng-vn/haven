# Loop journal

Newest entry first.
The loop reads this at every iteration start and appends at every iteration end.
See `graph/GOAL.md` for the rules. That file is user-owned; the loop never edits it.

Real measurements belong here. Real names and message content do not.

## Standing state

- Open PRs: none
- Build position: not started, next is P2 step 1 (extraction)
- Blocked on user: Ollama, the plan's default local provider, not yet installed (needed only at P2 step 7)
- Next intent: scaffold the Xcode project under `graph/`, add `.gitignore` before anything touches real data, then begin extraction

## Entries

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
