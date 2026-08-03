# Standing loop goal: connection graph

Read this file and `graph/JOURNAL.md` at the start of every iteration, before choosing any work.
This file is owned by the user. The loop never edits it; propose changes in the journal instead.

`graph/PLAN.md` is the design spec and the source of truth for what to build and why.
When something here seems arbitrary, read the matching section there before concluding anything.

## Mission

Build the macOS connection graph described in `graph/PLAN.md`, then keep improving it.

It reads the user's own iMessage history and Contacts and draws the graph of everyone they know and how those people connect to each other.
It is a personal tool with exactly one user, never distributed.
"Done" does not end the loop. When the build completes, continue as a standing quality program over the same scope.

## Hard constraints

A violation is never an improvement, regardless of how good the idea looks.

1. **`chat.db` is opened read-only and never written, copied, or moved.** `chat.db` runs in WAL mode with Messages writing continuously, and recent messages live in `chat.db-wal` until checkpointed. `?immutable=1` skips the WAL, silently missing the newest messages and misbehaving against a live writer, so it is banned on the live database. Open plain read-only, expect participation via the `-shm` sidecar, and retry on `SQLITE_BUSY`. Copying it would duplicate every message body ever sent.
2. **Message text is never persisted.** It is read transiently by the model pass; only derived guesses are stored. Never write message text to disk, to logs, to the journal, or to a commit.
3. **No real personal data in git, ever.** No message text, no phone numbers, no names, no exported graphs, no screenshots containing real contacts, no database copies. Add `graph/.gitignore` covering build output, extracted data, and any local cache before the first data-touching commit.
4. **Nothing is uploaded.** The model pass defaults to a local provider, so message snippets never leave the machine; configuring a cloud provider is the single explicit exception and it is the user's choice. No graph data, no telemetry, no analytics, no server component of any kind.
5. **Stay inside `graph/`.** This lives in the euno-app repo but shares nothing with Haven. Never modify `convex/`, `src/`, `ios/`, `CHANGELOG.md`, `package.json`, or any root config. Haven's CI, changelog, and version numbers are not yours.
6. **Never merge to main.** Open PRs; the user merges.
7. **No production surface anywhere.** No deploys, no publishing, no distribution, no notarization work. This is a local tool.
8. Global rules apply in full: plain ASCII everywhere, conventional commits, TDD for logic, no agent or tool names in commits or PR bodies, no co-author footers.
9. **Never edit this file.**

## Standing blocked-on-user items

Prepare, then wait. Track readiness in the journal.

- Merging any PR.
- Choosing and funding a model provider or installing Ollama.
- Any decision that contradicts `PLAN.md` rather than refining it.

## Each iteration

1. Read `JOURNAL.md`, check `git status` and open PR state.
2. Pick the highest rung of the ladder below that has available work.
3. Do one coherent unit of work to completion: tested, verified, committed, pushed, PR opened or updated.
4. Update `JOURNAL.md`: done, in-flight, blocked, next intent.
5. Schedule the next wakeup per Pacing.

## Priority ladder

**P0. Repair.** Failing tests, broken builds, red CI. Before anything else.

**P1. Babysit.** Open PRs: CI green, review comments addressed. Cap of 3 open PRs. At the cap, do commit-light work instead: self-review, journal planning, scratchpad experiments.

**P2. Build, in the order given in PLAN.md.**
1. Extraction from `chat.db` and Contacts into a working model.
2. Identity resolution, names and photos from Contacts.
3. Non-person filter, tuned against real results.
4. Graph construction: nodes, edges, pruning.
5. Layout, render, assembly animation.
6. Interaction: focus, time filter, toggles.
7. Model pass for unnamed handles, asynchronous after render.
8. Persistence and resync.
9. Export.

Step 5 is the first moment the tool is worth looking at. Everything before it is invisible plumbing. Get there fast.

**P3. Tune against reality.** The filter thresholds, the group-liveness bar, the edge pruning, and the label density are all calibrated guesses. Measure them against the real database, report the numbers in the journal, and adjust. This rung stays open permanently and is the main reason the loop keeps earning its keep after the build.

**P4. Quality passes.** Test depth, edge cases, accessibility, performance at ~700 nodes, animation feel, copy, refactors for clarity.

**P5. Horizon check**, at most once per week of loop time. Re-verify assumptions that could rot: macOS schema changes, model provider pricing. Date it in the journal.

If every rung is exhausted, extend P4. If that saturates, heartbeat rather than manufacture work.
Ideas outside this scope go in the journal as suggestions for the user, not into the code.

## Quality bar

A change qualifies only if all hold:

- It fixes a named defect or closes a named gap, recorded in the journal entry.
- Logic changes follow TDD: failing test first, for the right reason, then implementation.
- Tests pass, including the Swift test target.
- No new dependency without a written reason.
- You would approve the diff as a reviewer with no context beyond the diff.

Churn is not improvement: no renames for taste, no comment noise, no speculative abstraction, no reformatting passes.
An iteration that finds nothing qualifying says so in the journal and moves down the ladder. That is honest, not a failure.

## Testing with real data

Real data is available and is the only honest way to tune the filters.
But tests must be deterministic and must not depend on a database that changes daily.

The split: **tune against real data, assert against fixtures.**
Build small synthetic fixtures covering the shapes that matter (shortcode, never-replied thread, degenerate 2-member group, multi-service duplicate handle, large group) and write assertions against those.
Use the real database for measurement and calibration, and report findings as numbers in the journal, never as committed data.

## Workflow

One worktree per branch under `.worktrees`, absolute paths in every command, `cd` per call.
This repo has a documented history of edits landing in the wrong copy because of persistent shell cwd. Take it seriously.

Branch names: `graph/<topic>`.
PR bodies include a plain-language TLDR.
Never force-push main. Force-push only your own branches, and after an upstream squash-merge use `rebase --onto` rather than merging main in.
After the user merges, remove the worktree, delete the branch, journal it.

## Pacing

Self-pace with ScheduleWakeup, passing the same loop prompt through each time.
Actively working: continue immediately.
Waiting on CI or review only: 20 to 30 minutes.
Blocked everywhere or saturated: 60 minutes.
Never stop on your own initiative. The loop ends when the user says stop or usage runs out.

## Journal discipline

Newest entry first, one per iteration, timestamped.
Each entry: DONE with PR numbers, IN-FLIGHT with CI state, BLOCKED, NEXT intent, and any suggestion for the user.
Keep a short standing-state block at the top current.
Trim entries older than two weeks into a one-paragraph summary.
Numbers measured against the real database belong here. Real names and message content do not.
