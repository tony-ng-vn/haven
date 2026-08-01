# Loop journal

Newest entry first.
The loop reads this at every iteration start and appends at every iteration end.
See `graph/GOAL.md` for the rules. That file is user-owned; the loop never edits it.

Real measurements belong here. Real names and message content do not.

## Standing state

- Open PRs: none; #189, #190, and #192 all merged to graph-main 2026-07-31 with CI green
- Build position: all nine build-order steps merged, and the acquaintance layer now sits on top of them (derivation, marker override, JSON export, viewer v4, app bundling). 227 Swift tests plus 31 viewer node tests green. The native Canvas render still presents the bipartite model; its migration is the next build item.
- Goal-criteria status: (1) build order complete: YES. (2) suite green with every charter fixture shape: YES, audited (shortcode, never-replied, two-member style-43, multi-service duplicate, large group, empty chat row - each covered at one or more pipeline layers). (3) real-data pipeline run with journaled counts and a names-attached kill-list review: YES (iterations 3 and 4). (4) fixture e2e resync survival: YES (EndToEndResyncSurvivalTests). (5) export writes a high-resolution image: YES, headlessly proven. (6) app builds and launches with a plain permission explanation: implemented and launch-verified programmatically; ON-SCREEN confirmation is the one remaining gap, blocked on the locked session.
- Waiting on user: unlock the session (visual pass runs immediately), install Ollama + a model for live guesses, grant the app FDA for the first real in-app import
- Pending visual check: the machine's session was locked during iteration 5, so the on-screen look of the permission screen and the real-data render are unverified; first task once the session is unlocked
- Integration branch: `graph-main`, created 2026-07-31 per owner directive; the loop merges its own PRs there after green CI and self-review, main stays untouched, user merges graph-main to main
- Journal discipline: the canonical charter and journal copies live in the main checkout at `graph/`; the loop mirrors them into the graph-main worktree and commits there, always editing the main-checkout copy first
- Blocked on user: Ollama, the plan's default local provider, not yet installed (needed only at P2 step 7)
- Next intent: migrate the native render to the acquaintance presentation, then P3 tuning of the tier thresholds against the measured 100-strong/959-likely split

## Entries

### 2026-07-31 evening: owner decision, the two-plane sky returns (PR #192)

The owner compared the acquaintance-map demo against the original design artifact (the two-plane sky: group chats floating above as a labeled constellation plane, people ranked by closeness in rings below, evidence lines cascading between) and decided that design is the product's SKY presentation, in the app and in marketing embeds.
The acquaintance layer stays the shared model; the people-only map remains the analysis view via the exports workflow.
PLAN.md's Visual section now records this as two presentations over one model, restoring rings for the Sky view specifically.

DONE

- template-sky.html restored verbatim from the checkpoint commit (2,756 lines; deleted earlier today, recovered from git history exactly as the owner approved it).
- build.py: the viewer-core placeholder is conditional (absent skips inlining, present inlines exactly once, duplicates fail loudly); the JSON placeholder stays required exactly once. The skip was proven real, not vacuous: byte accounting matched the JSON payload exactly, zero core function names in the sky output, and a map build after the change diffed byte-identical to before.
- App bundles template-sky.html alone (map template and core file out of the bundle); SkyExportBuilder's viewer-core source is optional under the same conditional contract, red-first tested in both directions; AppModel and SkyView updated. The onboarding sky renders the two-plane design again.
- The landing's sample sky was rebuilt from template-sky.html with the synthetic fixture, so the marketing demo matches what the app shows.

VERIFIED BY THE LEAD

- swift test 228/0, swift build -c release clean, xcodebuild BUILD SUCCEEDED with template-sky.html present in the bundle and the map resources absent, node tests.mjs 31/31.

KNOWN CAVEAT

- The restored template ships unaudited, as approved: it carries the previously flagged potential bug where its time-travel init loop may overwrite adapter null fields with random values. Revisit if the sky misbehaves on real data.

NEXT

- Refresh the downloadable YourSky.zip from this build after merge.
- The native Canvas render migration and the P3 threshold tuning stand as queued.

### 2026-07-31: the acquaintance pivot (PR #190, after checkpoint PR #189)

The owner redirected the product abstraction in a design session: this is a personal acquaintance graph.
People are nodes, connections between people are the visible structure, group chats are hidden evidence explaining those connections, and the user is implicit -- no center node, no rings, no closeness tiers.
PLAN.md was amended accordingly ("What this is", a new "The acquaintance layer" section, a rewritten Visual contract, Interaction), canonical copy and worktree mirror kept identical.

DONE

- Checkpoint first (PR #189, merged): two prior sessions had left roster-keyed group dedup, the corrected roster classification, the onboarding flow, the viewer, and the Polygres sync script uncommitted in the worktree. Verified before landing (swift test exit 0 on that tree; the modified perf smoke inspected against the handoff's tamper warning and found to be the legitimate calibration rework; templates confirmed placeholder-only; sync script credential-free), then committed as one baseline.
- Acquaintance derivation in GraphCore: per shared chat, base weight 1/(n-1) with n the resolved members excluding the user, plus 0.1 per co-active day of the pair in that chat capped at 5; dead groups count in full; tiers strong >= 1.0 and likely >= 0.2, nothing recorded below; constants in AcquaintanceScoring for P3 tuning. GraphBuilder now emits GroupChatActivity (per-merged-chat member day sets) through a new buildDetailed, with build() unchanged for all existing call sites; service-split chats contribute once, unioned.
- The marker: "everyone here knows each other" stored as fullyAcquaintedRosterKeys (sorted member identifiers), translated at match time by identifier containment (AcquaintanceRosterKey.resolve) so a member's Person.id shifting across a resync cannot silently detach a marking -- the same philosophy HiddenNodeOverride already uses for people. Dormant keys match nothing and are never rewritten. Surfaced as a checkable group context-menu item in the app, persisted through the overrides store.
- Export and CLI: GraphJSON gains acquaintances (pair, tier, score, per-chat evidence with chatName echoing the nodes array) and fullyAcquaintedChatIds, deterministic, with tests pinning that no exported id dangles outside the nodes array. New counts-only acquaintances subcommand.
- Viewer v4 replaces the rings: people-only 2D pan/zoom map, seeded deterministic layout (groups as invisible anchors plus acquaintance springs), seeded label-propagation regions captioned by their dominant named chat, semantic zoom (rest shows dots, region labels, top names, strong-and-confirmed lines only; selection reveals a person's connections with evidence; pair selection shows the shortest observed path with per-hop evidence or a no-observed-path answer with shared-chat fallback), groups drawer with the marker toggle (localStorage marks keyed by chat plus roster, stale marks ignored, copy-marks-as-JSON), search, assembly animation honoring prefers-reduced-motion. viewer_core.mjs is the single tested-and-shipped source, inlined by build.py, which now requires its template argument and asserts each placeholder exactly once. Old templates deleted.
- App integration: project.yml bundles template-v4.html and viewer_core.mjs; SkyExportBuilder fills both placeholders in-process, mirroring build.py's strip (cross-referenced comments so they cannot drift silently), asserting exactly-once; the onboarding sky WKWebView now renders the acquaintance map.
- Real-data measurement (full history): 1,059 acquaintance pairs = 100 strong + 959 likely, 0 confirmed (no marks yet). The rest-state map draws only the 100 strong lines. P3 watch: whether the 0.2 likely floor under-includes regulars of the 18-to-20-member chats.

VERIFIED BY THE LEAD (not just agent reports)

- swift test 227 tests 0 failures; swift build -c release clean; xcodebuild BUILD SUCCEEDED with both viewer resources confirmed inside the built bundle; node tests.mjs 31/31; build.py against the synthetic fixture leaves no placeholder. Templates and fixtures hold no real data.

PROCESS

- Three delegated work packages (core derivation, viewer, app integration) plus two corrective re-briefs (resync-safe marker matching; the v3-to-v4 bundling seam). The lead made zero code edits; lead-authored changes were PLAN.md and this journal.
- The viewer suite is partially not red-first: layout and community expectations were derived empirically against the fixture, then locked in and mutation-tested; one vacuous test was caught by deliberate mutation and rewritten around a scenario that actually exercises the guarded path.
- One cross-agent seam bit mid-session: renaming the viewer template broke the app's bundled-resource build while both agents were in flight. Isolated cleanly by the core agent's report; fixed as its own integration pass.

BLOCKED / NEXT

- Native Canvas render and image export still present the bipartite model; migrating them to the acquaintance contract is the next build item.
- No import path yet from the viewer's copy-marks-as-JSON into the app's override store.
- Pre-existing CLI gaps, noted and unchanged: json/acquaintances apply neither removed/hidden overrides nor an injectable overrides path.
- prune() remains uncalled by AppModel; the minStrength question is still P3 measurement.
- The session handoff file (HANDOFF.md) is deleted; every open item it carried is either done in #189/#190 or recorded here.
- Owner-directed web landing work (Haven landing, Sky download page, iOS waitlist page) proceeds in the Haven repo outside this charter's scope; the downloadable YourSky.zip is being rebuilt from this PR's code so the shipped app carries the new map.

### 2026-07-31: roster-based group dedup, three cleanups, one-click copy

DONE

- Group identity now comes from the resolved roster, not the chat row. Apple writes one `chat` row per service, so a single human group appeared twice, once for iMessage and once for SMS/RCS: 9 redundant group nodes across 8 clusters on real data. Chats whose resolved rosters match now merge into one node.
- Name guard, because two chats can legitimately share a roster: within a roster bucket, zero distinct names merges everything unnamed, exactly one distinct name merges everything under it, and two or more names split into one node per name with each unnamed chat standing alone rather than being attributed to a name it may not belong to.
- Merged node id is `chat:<lexicographically smallest guid>`. Min-by-guid, not min-by-rowID: rowID is a local sqlite artifact that renumbers across a resync, guid does not.
- Message activity is unioned at the message level, never by summing `distinctDays`, so a day spoken on both iMessage and SMS counts once. Liveness, per-member edge strength, and the user edge strength all read the union.
- Six tests added, including one beyond the four originally specified: two same-roster chats active on different single days, each dead alone, live once merged, with member and user edge strengths asserted against the union.
- Cleanups: the rest-state edge-opacity formula was copy-pasted in `GraphImageRenderer` and `GraphView` under a comment claiming it was already shared, and is now genuinely shared as `EdgeRenderList.opacity(forStrength:)` with the comment corrected. Three `distinctDays` copies collapsed into `ActivityDays`. Roster resolution, duplicated at five sites, collapsed into `ChatRoster`.
- One-click copy of a phone number added to both frontends at the user's request: a real `<button>` in the viewer's detail panel (keyboard-operable for free, aria-label naming what gets copied, async clipboard with an `execCommand` fallback and a visible failure state, since the page is opened from `file://`), and a `CopyableIdentifier` button in the app's merge queue that writes to `NSPasteboard`.

VERIFIED

- `swift test`: 195 tests, 0 failures. `swift build -c release`: clean. `xcodebuild -scheme ConnectionGraph`: BUILD SUCCEEDED.
- The viewer's script body passes `node --check`, and the page renders from a synthetic export. The on-screen click was NOT verified: the browser extension was not connected. That check is still outstanding.

BLOCKED / NEXT

- Hide-state hazard introduced by the merge, not yet fixed: `HiddenNodeOverride` rebuilds `chat:<guid>` from the stored guid and looks it up in the graph, so if a resync surfaces a service-split chat with a smaller guid, the merged node's id changes and the user's hide silently detaches. The same file already solves this for people by matching any of a person's identifiers rather than one possibly-stale id; the group side wants the same treatment. `EndToEndResyncSurvivalTests` cannot catch this today, since its fixture builds only one chat per group.
- `PersonFilter`'s `groupMemberships` count still counts one human group once per service, which feeds the never-replied removal rule. Left alone: the cleanup pass was a mechanical extraction, and changing this is a semantics change worth its own iteration.
- `prune()` stays uncalled by `AppModel`, per the user. The open question is not whether to call it but what `minStrength` should be, which is a P3 measurement, not a guess.

### 2026-07-31: user authorizations on record, moved out of the charter

Two sessions amended `GOAL.md` in place, one rewriting constraint 4 and one rewriting constraint 7.
Both edits violated the charter's own rules: line 4 says the file is user-owned and the loop never edits it, and constraint 9 says never edit this file.
The user confirmed both underlying authorizations are real, and directed that the charter text be restored and the authorizations recorded here instead.
`GOAL.md` is back to its committed wording. Authorizations live in this journal from now on; propose charter changes here, never in that file.

Authorizations on record:

- 2026-07-31, uploading derived graph exports (nodes and edges only, never message text) to the Haven Polygres project `pa6ee1830f10557dcc9bfd0c`, so the agent has a queryable store of the relationship network. Already executed: 684 nodes and 1014 edges loaded. Constraint 2 stands on its own and is not weakened by this: message text is never uploadable under any authorization.
- 2026-07-31, building a download landing page on the Haven web app and an unsigned distributable build of the graph app as the MVP onboarding flow. Notarization and signing stay blocked on the user's Apple Developer account. Note that the landing-page half lives outside `graph/`, which constraint 5 puts out of this loop's bounds; it needs the user working in the Haven repo directly, not the loop.

### 2026-07-31 iteration 12: visual pass, goal criteria complete

DONE

- The session unlocked at about 10:50; the visual pass ran immediately. The app was built fresh from merged graph-main and launched via `open` (no Full Disk Access identity): the permission state rendered on screen with its explanation text, and System Settings was observed open at exactly the Privacy & Security > Full Disk Access pane. Screenshot was window-region only, viewed, and deleted; nothing committed.
- The user was present, engaged with the permission flow, and closed the app; no further windows were pushed onto their screen. The real-render moment belongs to them by the goal's own definition.
- ALL SIX goal criteria now hold: (1) all nine build-order steps implemented and merged; (2) 145 tests green covering every charter fixture shape plus empty-chat-row and two-member style-43; (3) the full pipeline ran against the real chat.db and Contacts from the terminal, node and edge counts journaled (669 nodes, 943 edges), never-replied kill list reviewed with names attached; (4) EndToEndResyncSurvivalTests proves hidden, removed, and merge answers survive a resync with renumbered row ids; (5) export writes a high-resolution PNG, pixel-verified headlessly; (6) the app builds, launches, and a launch without permissions explains exactly what to grant and where, confirmed on screen.
- The standing loop continues past "done" as a quality program per GOAL.md; the goal directive's build-to-completion condition is met.

REMAINING FOR THE USER (the goal's own closing list)

- Grant Full Disk Access to ConnectionGraph.app (the + button in the FDA pane; the built app is at .worktrees/graph-main-wt/graph/App/DerivedData/Build/Products/Debug/ConnectionGraph.app), press Try Again, and look at the graph.
- Optionally: install Ollama plus a small model to enable name guesses; decide the iteration-3 liveness-bar proposal; merge graph-main to main whenever wanted (user-only per the charter).

### 2026-07-31 iteration 11: density instrument (PR #188)

DONE

- Heartbeat found the session still locked; picked the one qualifying P4 item from the backlog instead of idling: the CLI's edges-per-node figure was not comparable to the plan's calibration definition (named in iteration 4). DensityMetric.planComparable added with discriminator tests (user-group edges provably not in the numerator, dead groups provably not in the denominator); CLI prints both figures under honest names. 145 tests green (4 new, red-first).
- Real-data measurement with the corrected instrument: edgesPerNodePlanComparable = 1.36, against the plan's 1.19 projection and the 1.04 reference image. The real graph runs about 14 percent denser than projected; the P3 pruning conversation starts from 1.36, not 0.85 or 1.19. (If the iteration-3 liveness proposal is adopted, re-measure: it adds up to ~150 degree-1 people, which would LOWER this figure.)

IN-FLIGHT

- PR #188 against graph-main, waiting on CI.

BLOCKED

- Visual pass (session locked; unlock monitor armed). Live Ollama pass. Liveness-bar decision.

NEXT

- Merge #188 on green, then back to heartbeat until unlock.

### 2026-07-31 iteration 10: build phase closed

DONE

- #187 merged to graph-main after green CI and lead review; worktree and branch removed. All nine PLAN.md build-order steps are now implemented and merged: extraction (#179), identity (#180), filter (#181), construction (#182), render and app (#183), interaction (#184), persistence and resync (#185), export (#186), model pass (#187). Nine PRs, all squash-merged to graph-main by the loop per the owner's goal directive; main untouched throughout.
- Fixture-shape audit (goal criterion 2) completed: every shape the charter's testing section names, plus the goal's empty-chat-row and two-member style-43 additions, is covered by committed fixture tests, most at several pipeline layers. 141 tests green.
- Goal-criteria sweep recorded in the standing state above: five of six criteria fully met; criterion 6's on-screen confirmation is the single remaining item, blocked on the locked session. The loop keeps a heartbeat and runs the visual pass the moment the session unlocks.

BLOCKED

- Visual pass (session locked). Live Ollama pass (not installed). Liveness-bar refinement decision (iteration 3 proposal).

NEXT

- Heartbeat per pacing. On unlock: full visual pass (permission screen via open, real render via direct binary run with terminal FDA, gestures, focus, toggles, merge queue, resync, export; screenshots to scratchpad only, deleted after; findings journaled as aggregates). Then P3 tuning against the real render (centering strength at 630 nodes, label density, liveness-bar proposal if approved).

### 2026-07-31 iteration 9: model pass (PR #187)

DONE

- #186 merged to graph-main after green CI and lead review; worktree and branch removed.
- The last build-order step: SnippetReader (the single file allowed to SELECT message.text, loudly marked; newest-20 sample, NULL text skipped), GuessPrompt, NameGuessProvider protocol, OllamaProvider (localhost /api/generate, strict JSON, unreachable-vs-bad-response taxonomy, URLProtocol-stubbed tests, ephemeral no-cache URLSession so prompts cannot hit disk via the network stack), GuessEngine (serial, cancelable, skips cached, stops on unreachable, skips bad responses), NodeLabel (tilde-marked guesses on screen AND export). Toolbar progress chip with an install-Ollama note when the provider is missing. 141 tests green (29 new).
- The privacy proof: the engine runs over sentinel message text, overrides are saved, and the raw JSON bytes on disk contain the guess but never the sentinel. A tree-wide grep confirms sentinels appear nowhere outside test files.
- Two review-caught bugs fixed red-first: a cancellation race on the final candidate reporting completed instead of cancelled, and the group cache-key transform duplicated on read and write sides (would have silently orphaned every group guess if drifted).
- Open semantics flagged for the record: guesses sample the full history, not the current time filter (deliberate); all transport errors stop the pass (fine for a local server); the progress chip counts successes only.

IN-FLIGHT

- PR #187 against graph-main, waiting on CI.

BLOCKED

- Live guess pass: Ollama not installed (the code is complete; installing Ollama plus a model is the only remaining step).
- Visual pass: session still locked.
- Liveness-bar refinement decision from iteration 3.

NEXT

- Merge #187 on green. Then the charter testing-section fixture audit (goal criterion 2): verify every named shape is covered (shortcode, never-replied thread, degenerate 2-member group, multi-service duplicate handle, large group, empty chat row) and close any gap. Then P3/P4 work until the session unlocks for the visual pass.

### 2026-07-31 iteration 8: export (PR #186)

DONE

- #185 merged to graph-main after green CI and lead review; worktree and branch removed.
- NodePalette (single color source for screen and export), GraphImageRenderer (pure CoreGraphics/CoreText, headlessly tested down to individual pixels: dimensions, node-center colors, hidden-node absence, label ink tracking name content, byte-identical determinism, the screen's sqrt-strength edge opacity), GraphImageExport (ImageIO PNG writing), and the app's Export button with save panel. Export labels every named node, deliberately ignoring the screen's top-40 budget. 112 tests green (10 new).
- Real bug caught by an exact pixel probe: CGColor built in generic sRGB against a device-RGB bitmap context shifted stored bytes up to 7 percent; colors now constructed in the context's own space. The y-flip convention was settled by a standalone row-order experiment before the suite depended on it.
- Goal criterion 5 (export writes a high-resolution image) is implemented and headlessly proven; visual confirmation of a real export rides the unlocked-session pass.

IN-FLIGHT

- PR #186 against graph-main, waiting on CI.

BLOCKED

- Visual verification of the app (permission screen, render, gestures, save panel): needs the user's session unlocked.
- Ollama install for a LIVE model provider (P2 step 7's code arrives next iteration against a stubbed provider).
- Liveness-bar refinement decision from iteration 3.

NEXT

- Merge #186 on green. Then P2 step 7: the model pass code - provider protocol with an Ollama HTTP implementation, transient snippet reading (never persisted), guesses cached in the overrides store's nameGuesses slot keyed by normalized identifier, asynchronous label refinement after first render - fully tested against a stubbed provider so only the user's Ollama install stands between the code and live guesses.

### 2026-07-31 iteration 7: persistence and resync (PR #185)

DONE

- #184 merged to graph-main after green CI and lead review; worktree and branch removed.
- Overrides store (JSON at Application Support/ConnectionGraph/overrides.json, injectable path, atomic writes, backward-compatible decode, corrupt file fails loudly): hidden person identifiers, hidden group guids, removed identifiers, merge answers, and an empty name-guess slot for step 7. IdentityResolution accepts asserted merges; suppression, removal, and hidden-mapping helpers; app gains Remove person, Restore All, merge-questions popover, Resync. 102 tests green (18 new), red-first per area.
- The goal's acceptance criterion 4 is now proven by EndToEndResyncSurvivalTests: two independently built chat.db fixtures with all ROWIDs shifted +100 between them, overrides round-tripped through disk with a fresh store instance, asserting hidden person AND hidden group survive, removed stays removed, user-merged pair stays one person, answered candidate is regenerated then suppressed. Mutation-verified non-vacuous.
- Two bugs caught in second-pass self-review before handoff: Keep separate suppressed against the wrong people list (post-filter instead of pre-filter) and Removed:N counted identifiers not people.
- Still unverified by launch: all new UI, queued for the unlocked-session pass.

IN-FLIGHT

- PR #185 against graph-main, waiting on CI.

BLOCKED

- Visual verification of the app: needs the user's session unlocked.
- Ollama install (P2 step 7).
- Liveness-bar refinement decision from iteration 3.

NEXT

- Merge #185 on green. Then P2 step 9 (export: high-resolution image with real names, hide-before-export already exists via the hidden mechanism). After that, the remaining goal criteria are the model pass (Ollama) and the visual pass (unlocked session).

### 2026-07-31 iteration 6: interaction (PR #184)

DONE

- #183 merged to graph-main after green CI and lead review; worktree and branch removed.
- FocusSet (one-hop highlight; user focus lights all involvesUser edges per the plan's "who connects to me"; a person's own user edge included, a group's not), TimeFilter (inclusive range over messages; end-to-end test proves downstream rules need no changes), Graph.excludingNodes (render-only hide with degree recompute), HitTest (single source of truth for the draw transform and its inverse, 8 tests). ForceSimulation gains includeDeadGroups. App: toolbar with date range, dead-group toggle, hidden count and unhide, focus chip; tap-to-focus; right-click hide; Escape clears. 84 tests green, 19 new, red-first with two test-authoring bugs caught during red.
- A per-frame linear-scan perf bug in the highlighted-edge draw path (about 200k string compares per frame with the user focused) was caught in second-pass self-review and fixed with init-hoisted dictionaries before handoff.
- Session still locked; the visual pass now covers both rendering and live gesture behavior (tap vs pan precedence, context-menu hover targeting, Escape routing). All logic beneath the gestures is unit-pinned.

IN-FLIGHT

- PR #184 against graph-main, waiting on CI.

BLOCKED

- Visual verification of the app: needs the user's session unlocked.
- Ollama install (P2 step 7).
- Liveness-bar refinement decision from iteration 3.

NEXT

- Merge #184 on green. Then P2 step 8 (persistence and resync with the overrides store keyed by normalized identifier: hidden stays hidden, removed stays removed, merge answers never re-asked), including the charter's required fixture-based end-to-end resync-survival test. Step 7 (model pass) waits on Ollama; step 9 (export) after 8.

### 2026-07-31 iteration 5: layout, render, app (PR #183)

DONE

- #182 merged to graph-main after green CI and lead review; worktree and branch removed.
- ForceSimulation in GraphCore: deterministic (stable-hash seeding, pinned literals verified across processes), user pinned at center and force-exempt, dead groups and user edges excluded, strength-scaled springs, NaN-safe. 65 tests total. Perf smoke at real scale: 0.36ms per tick release (45x headroom at 60fps), 29ms debug.
- Two engine bugs found by measurement, not inspection: a spring-force sign inversion (positive feedback that read as slow settling; caught by printing positions against hand-derived expectations) and a damping value that let alpha decay freeze clusters before separation (swept 0.5-0.9, shipped 0.75, separation ratio 2.26; restLength turned out NOT to be the lever, correcting the earlier hypothesis).
- LabelBudget (top 40 by degree, deterministic ties) and EdgeRenderList (never user edges, never dead groups), both red-first tested.
- The app: graph/App via XcodeGen (repo iOS precedent), ConnectionGraph.app, no sandbox (FDA requires non-sandboxed), ad-hoc signing. States: loading, needs-permission (plain-language FDA instructions plus an Open System Settings button using the Privacy_AllFiles pane URL and a note that contacts arrive through the same grant), ready (Canvas + TimelineView, assembly animation about 4.4s, zoom and pan), failed. Built clean twice including a fresh-DerivedData rebuild.
- Launch verification: the app launches and runs its event loop cleanly (process sampled healthy). The session was password-locked at 4am, so macOS deferred window creation and no screenshot was possible; the visual pass (permission screen, then real-data render) is queued as the next unlocked-session task. No lock-screen interaction was attempted.
- Real-scale layout extent flagged by measurement: settled mean node distance ~608, max ~1045 on a 1200x900 window, so the rest state overflows the window without zooming out. Centering-strength scaling at ~630 nodes is queued for the P3 tuning pass against the real render.
- Process notes: pass 1 disclosed a TDD-order deviation (tests written first but red captured retroactively via a stub; the retroactive red itself caught a vacuous NaN test, fixed). Pass 2 was red-first properly. TimelineView keeps redrawing after settle; P4 energy nit.

IN-FLIGHT

- PR #183 against graph-main, waiting on CI.

BLOCKED

- Visual verification of the app: needs the user's session unlocked.
- Ollama install (P2 step 7 only).
- Liveness-bar refinement decision from iteration 3.

NEXT

- Merge #183 on green. Then P2 step 6 (interaction: focus mode revealing ego edges, time filter, dead-group toggle, hide nodes), with the unlocked-session visual pass first whenever it becomes possible.

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
