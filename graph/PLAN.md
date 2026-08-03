# Connection graph: product plan

Status: built through the original nine steps; design amended 2026-07-31 with the acquaintance layer below.
Date: 2026-07-31.
Location: `graph/` inside the euno-app repo. Separate product from Haven, shares no code with it.
Product name: TBD.

This is a **personal tool**, built by its only user, for that user, never distributed.
That single fact removes most of the constraints that would otherwise dominate this document.

Platform research behind the hard constraints: `docs/2026-07-30-imessage-connection-graph-research.md`.

---

## What this is

A macOS app that reads your own iMessage history and Contacts, and draws your personal acquaintance graph: everyone in your social world, and how those people appear to be connected to one another.

The graph is the product.

Messages are evidence, group chats are contexts, people are nodes, and the product is a navigable map of the connections among them.
The messages themselves are implementation detail: the user never browses threads here, they see the map those threads imply.

It answers two questions:

1. Who is in my world.
2. Who in my world appears to know whom.

Because everyone on the map is someone the user knows, the user themself is implicit.
A line from the user to every node adds no information; the canvas as a whole is already "your world".

It is a tool you keep using, not a one-time artifact.
It stays current through resync, and you explore it rather than just look at it.

---

## Measured reality

Taken from the real database on 2026-07-31, metadata only.
These are facts, not estimates, and the design is calibrated to them.

- 110,096 messages, October 2022 to present, 177MB.
- 2,160 handle rows, 1,918 distinct identifiers. The gap is the same person appearing under multiple services.
- 1,320 chats: 1,190 one-to-one, 130 group. Of the 1,190 one-to-one chat rows, 1,047 contain at least one message; the other 143 are empty rows, drafts and cleared conversations that Messages keeps around.
- Service mix is **SMS 1,163, iMessage 655, RCS 342**. SMS dominates. Nothing may assume iMessage.
- 213 handles are shortcodes that fail phone-number parsing outright.
- 8,342 Contacts records, against only ~615 people who actually appear in messages.

**Reciprocity is the dominant filter.**
Of the 1,047 one-to-one chats that contain any messages, **589 have no reply from the user at all**.
That one rule removes 56% of the noise before any other heuristic runs.

**Group sizes are bimodal.**
81 groups have 5 or fewer members.
21 sit between 18 and 20 members, plus singles at 26, 28, 31, and 32.
That 32-person chat would alone manufacture 496 false friendships under naive projection, which is why the model is bipartite.

**Projected graph under the rules below: 615 people plus 74 live group nodes, so 689 nodes, and 820 edges.**
That is 1.19 edges per node.
The reference screenshot that inspired this runs 1.04.
The pruning rules are calibrated, not guessed.

---

## Hard constraints

**iOS is impossible.**
No API, entitlement, or permission on iOS can read Messages data, ever.

**Full Disk Access cannot be prompted for.**
The user grants it once by hand in System Settings.
For a personal tool this is a one-time setup step, not a product problem.

**Read-only, always.**
`chat.db` is opened read-only and never written, never copied, never moved.
Copying it would duplicate every message body ever sent, which defeats the point.

---

## Product shape

A living tool.

First run imports and renders with an animated assembly, which is the introduction to how the graph reads.
After that it is something you open, explore, filter, and resync.

Resync rebuilds from the current database.
At 110k messages a full rebuild is fast enough that incremental diffing is not worth the complexity.
User curation survives resync.
Hidden nodes stay hidden, removed nodes stay removed, answered merge questions are never re-asked.
Overrides live in their own store, keyed by normalized identifier (E.164 or lowercased email), never by database row ids, which renumber.
After every rebuild, the overrides re-apply.

Export produces a high-resolution image with real names, and lets you hide specific nodes before exporting.

---

## Nodes

Two types.

### People

**Nodes come from messages, not from Contacts.**
This is important: the address book holds 8,342 records against ~615 people who actually appear in messages.
Including all of Contacts would put roughly 7,700 isolated dots on screen, each with no edges or a single line to the user, burying the real graph.

**Contacts never creates a node.**
It supplies names, photos, merge evidence for identity resolution, and a human signal for the filter, all attached to nodes that messages create.

A person earns a node if they appear in a live one-to-one thread or a live group chat, where "live" means activity across two or more distinct days.

Non-people are filtered on metadata alone, in this order:

- Shortcodes: 4 to 6 digit senders that fail phone-number parsing. There are 213.
- Alphanumeric sender IDs: contain letters, cannot receive replies at all.
- **Never replied**: no outbound message from the user across the entire thread history. This is the strongest signal, flagging 589 of the 1,047 one-to-one chats with messages; the Contacts override below spares the saved ones, and the rest are removed.
- Metronomic timing: fixed daily schedule, or arrival seconds after the user acted elsewhere, which is the one-time-passcode signature.
- Business-hours-only traffic across months with no evenings or weekends.

Two positive signals outrank the above.
A handle appearing in a group thread alongside confirmed humans is almost certainly human.
Automated senders do not get added to group chats.
A handle matching a Contacts card is human, period; never-replied does not remove it.
Saved-but-noisy entries (a saved cable company) get included, and the user hides them.

Ambiguous handles are included rather than dropped, and the user removes them if they intrude.
A dentist on a normal number that you once replied to passes every filter, and a real person you never replied to looks exactly like spam.

Handles with no contact card are included, labeled by number plus a model-derived guess at who they are.
The guess is always visibly marked as a guess.

No nodes for people never contacted.

### Group chats

A group chat is a node, not a set of person-to-person edges.

Only live groups qualify, measured by activity across distinct days rather than raw message count, because one frantic day of logistics can outproduce a year of a real group.
Of 130 groups, 74 clear a two-day bar and 38 clear a five-day bar.
Start at two days.

Roster comes from `chat_handle_join`: complete, and members who later left are historically true, which fits a graph built from all history.
Liveness and edge strength come from message activity, which the time filter needs per-message anyway.
A member who never posts still gets their group edge; a lurker in the college thread still belongs to the college cluster, and their edge is simply weak.

Dead groups are hidden behind a toggle, never deleted, so the bar can be loosened without re-importing.

Unnamed groups get the same model-derived guess as unnamed numbers.

36 chats have `style=43` (group) but only 2 members.
A chat's roster comes from `chat_handle_join`, which lists the *other* participants and never the user.
This was verified against the real database: all 1,191 `style=45` one-to-one chats have a roster of exactly 1.
A 2-member roster is therefore you plus two other people -- a real three-person group, not a one-to-one conversation.

Classification keys on the number of *distinct resolved people* in the roster, not on the raw row count, because two handle rows can be the same human on two services.
One distinct person renders as a one-to-one edge; two or more render as a group node.
Measured against the real database, correcting this surfaced 33 group chats that had previously been collapsed into one-to-one threads, three of which carry a real group name that was being discarded.
The same pass stopped rendering 22 groups whose every member is removed by the person filter, since a group with no surviving members is a node with nothing in it.
A synthetic fixture must cover both shapes: a 2-handle roster of two different people, and a 2-handle roster that resolves to one person.

---

## Edges

**One-to-one threads produce a direct person-to-person edge.**

**Group chats do not.**
The user connects to the group node, each member connects to the group node, and members are not connected to each other.

This bipartite model is chosen deliberately.
It costs 513 edges instead of many thousands, and it tells the truth: these people share a context, which is known, rather than these people know each other, which is not.
The relationship remains visible as two nodes hanging off a shared neighbor.
It is simply not a line.
What can honestly be drawn between two members is a derived edge with explicit confidence; that is the acquaintance layer below, and it never replaces the bipartite record, it summarizes it.

**One line per pair**, however many reasons underlie it.

**Every edge carries a source field** from the first commit, so adding call history later is a new ingest path rather than a reshape.

Reason and strength are computed and stored on every edge.
Strength is required whether or not it is displayed, because it decides which edges survive pruning.

---

## The acquaintance layer

The bipartite model above stores what is observed.
The acquaintance layer derives what it implies: person-to-person edges that answer "who appears to know whom", each carrying explicit confidence and inspectable evidence.

A shared group chat is a shared room, not proof of friendship.
That 32-person chat would manufacture 496 pairwise friendships under naive projection.
So co-membership is converted into confidence instead of asserted as fact.

Derivation runs over the built graph only, with no new database reads:

- A candidate pair is two surviving people who share at least one group chat's resolved roster.
- Each shared chat contributes a base weight of 1 / (n - 1), where n is the number of distinct resolved members in that chat, the user excluded.
  Two people alone in a trio chat with the user contribute 1.0; two members of a 20-person chat contribute about 0.05.
- Each shared chat adds 0.1 for every day both people were active in it, capped at 5 such days per chat.
  Lurkers who share a room but never overlap keep the base weight only.
- Dead groups count in full.
  Acquaintance does not expire when a chat goes quiet; liveness gates group-node rendering, not evidence.
- The score is the sum over all shared chats.

Tiers, from score:

- `confirmed`: the user has vouched for the pair via the marker below. Never produced by scoring alone.
- `strong`: score at or above 1.0.
- `likely`: score at or above 0.2.
- Below 0.2, no acquaintance edge is recorded.

Absence of an edge means "no observed evidence", never "these people do not know each other".
The weights and thresholds are calibrated guesses in the P3 sense: measure against the real graph, journal the numbers, tune.

**"Everyone here knows each other."**
The user can mark a group chat as fully acquainted, which promotes every pair among its resolved members to `confirmed`.
The marking is an override, stored with the rest of the curation, and it survives resync.
It is keyed by the chat's sorted resolved member identifiers, never by chat guid or row id: the people are the durable identity of the marking, so the key survives both resync renumbering and service-split merges.
Unmarking demotes the pairs back to whatever their observed score earns.

Evidence is stored on every acquaintance edge: each shared chat with its name, member count, and count of co-active days.
The interface can always answer "why do you think these two know each other" by listing exactly that.

One acquaintance edge per pair, however many chats underlie it.
The JSON export gains an `acquaintances` array (pair, tier, score, evidence) and a `fullyAcquaintedChatIds` echo, so the HTML viewer renders the same derivation the app computes.

---

## Pipeline

1. Read `chat.db` read-only (plain read-only open, never the immutable flag) and the Contacts database.
2. Normalize handles: phone numbers to E.164, emails lowercased.
3. Attach names and photos from Contacts.
   Contacts comes before filtering and identity resolution because a card naming both a phone number and an email is the join evidence for merging, and because the non-person filter must see names.
4. Resolve identity. Auto-merge only on exact matching normalized identifiers or identifiers co-listed on one Contacts card; queue anything uncertain.
   A wrong merge blends two people under one name and is expensive to unpick.
   A wrong non-merge costs one duplicate node.
   Err toward not merging.
5. Filter non-people. A handle matching a Contacts card is never removed by the never-replied filter.
6. Build nodes and edges. Group roster from `chat_handle_join`; liveness and edge strength from message activity.
   Acquaintance edges are derived in this step too, from the built graph alone.
7. Prune edges by strength, never a node's last edge.
8. Lay out, render, animate.
9. Model pass, asynchronous, after first render.

---

## The model pass

Task: given a set of message snippets from an unnamed handle or an unnamed group, return a likely name and a short description of who they are to the user.

It runs after first render, asynchronously.
The graph renders immediately from metadata; unnamed handles are labeled by their number, and labels refine in place as guesses arrive.
Guesses are cached, keyed by normalized identifier, so a resync only queries handles never seen before.

This is not a frontier-model task.
Provider is configurable.
Default is local, through Ollama: zero cost and zero data leaving the machine.
A cloud provider is an explicit opt-in, not a default.
Volume is a few hundred one-time calls.

**Message text is read transiently and never stored.**
Only the derived guess persists.
This is not a compliance requirement here, it is a design discipline that keeps the tool from becoming a second copy of the message archive.

---

## Visual

The map shows people, not plumbing.

- People are the visible objects.
- Connections between people are the visible structure.
- Group chats are hidden evidence, surfaced only when someone asks why a connection exists.
- The user is implicit: no center node, no rings, no depth hierarchy.
  Roughly half of all edges in the graph terminate at the user, which is exactly why they are not structure: rendered, they collapse every region toward one hub.
  The whole canvas is "your world", and the meaningful structure is the relationships among everyone else.

Position means shared context.
People sit near one another because they share conversations and mutual connections, so the canvas reads as social regions (family, work, the college thread) rather than as a solar system ranked around the user.
Force-directed layout still does the work: group chats act as invisible anchors pulling their members together, and acquaintance edges add springs between people, so regions fall out without a separate pass deciding positions.

Regions are labeled from evidence, not invented.
A region label comes from the dominant named group chat among its members; unnamed regions stay unlabeled rather than guessing.

Semantic zoom manages scale: every person is always present, but not every label and every line.

- At rest: every person as a dot, region labels, a few high-degree names, `confirmed` and `strong` edges as faint structure, `likely` edges hidden.
- Hover: the person's name.
- Select a person: their acquaintances light up with their lines, everything else dims, and a panel lists connections by tier with the shared-chat evidence behind each.
- Select two people: whether they connect, the shortest observed path between them, and the evidence for every hop.
- Bridge people, whose edges span regions, sit between regions and may be subtly emphasized; their position already tells the story.

Line style encodes confidence: solid for `confirmed` and `strong`, soft for `likely`, no line where there is no evidence.

**First run animates the assembly.**
Nodes fly in, the simulation settles over several seconds, then rests.
This is not only spectacle: watching regions separate teaches the viewer how to read the layout, which a static render cannot.

Node size scales with acquaintance count. Tunable.

**Owner decision, 2026-07-31 evening: the product has two presentations over the one model.**
The **Sky** is the two-plane render from the original design artifact: the group chats float above as a labeled constellation plane, the people sit below ranked by closeness in rings, and evidence lines cascade between the planes.
It is the emotional first-run view: what the app shows after "Map relationships", and what marketing embeds.
This deliberately restores the rings for the Sky view only, superseding the "no rings" line above for that view; closeness-to-you is the Sky's organizing question.
The **Map** is the people-only acquaintance presentation specified above (regions, semantic zoom, pair paths, evidence): the analysis view, built by the exports workflow (`template-v4.html`).
The acquaintance derivation, tiers, and the fully-acquainted marker are the shared model underneath both.

The native app's Canvas render still shows the earlier bipartite presentation (user node drawn, group nodes as objects, ego edges on focus); aligning it is follow-up work; the derivation and the override live in core either way.

**Owner decision, 2026-08-02: one presentation. The Sky is the product's only graph UI.**
The Map (`template-v4.html`, `viewer_core.mjs`) and the native Canvas render are deleted rather than maintained alongside; recover them from git history at PRs #190 and #192 if ever needed.
The acquaintance derivation, tiers, and the fully-acquainted marker remain the model underneath the Sky.
The people-only contract above (regions, semantic zoom, pair paths) stays in this file as design record; no shipped surface implements it today.
The bipartite image export goes with the Canvas render; the exported sky HTML is the shareable artifact.

---

## Stack

Swift and SwiftUI for the app, extraction, and model; the Sky presentation renders in a WKWebView from `template-sky.html` (owner decisions of 2026-07-31 and 2026-08-02 above supersede the original "no web view" line).
Contacts access is native, and the test expectations in `graph/GOAL.md` already assume a Swift test target.

---

## Interaction

In scope, because this is a tool used over time rather than a one-shot artifact.

- Select a person to see who they know; select two people to see how they connect. Both per the Visual contract above.
- The connection lens, the Sky's second-degree view (owner directive 2026-08-02).
  Click yourself: your inner circle, the first degree (shipped).
  Click a person: focus and their card (shipped).
  Double-click a person: the lens.
  The you-to-them focus treatment stays, and that person's own connections light up: every acquaintance edge from them to other people in the sky, drawn by tier (confirmed and strong solid, likely soft).
  Each revealed neighbor is visually marked by whether they also connect to you directly (a one-to-one thread with you) or are known to you only through shared groups.
  Esc or clicking empty space drops back to the plain focus; clicking another person moves the focus as it does today.
  An export without acquaintance data renders the sky with the lens inert, no errors.
- Search by name, since most dots are unlabeled at rest.
- Mark a group chat "everyone here knows each other", or unmark it.
- Filter by time, so the graph can show a chosen period rather than all history.
- Toggle dead groups on and off (native app; the viewer shows groups only as evidence).
- Hide nodes, both for readability and before export.
- Resync on demand.

---

## Build order

1. Extraction: read `chat.db` and Contacts into a working model. Real data from day one.
2. Identity resolution, plus names and photos from Contacts.
3. Non-person filter, tuned against real results. This requires names attached: a kill list of bare numbers cannot be eyeballed for false positives.
4. Graph construction: nodes, edges, pruning.
5. Layout, render, assembly animation. First visible payoff.
6. Interaction: focus, time filter, toggles.
7. Model pass for unnamed handles, asynchronous after render.
8. Persistence and resync, including the overrides store.
9. Export.

Step 5 is the first moment the thing is worth looking at, and everything before it is invisible plumbing.
Get there fast, then iterate.

---

## Deferred

- Stranger nodes: people mentioned but never contacted.
- Mention-derived edges: Sarah naming Mike creates a Sarah-to-Mike edge. Deferred because density already sits at 1.19 edges per node against the 1.04 reference before any mention lands, and because resolving a first name in text to one node among 615 people is guesswork. Would ride the existing edge source field when revisited.
- Call history as a second source. The edge source field keeps this cheap.
- Displaying reason and strength on the bipartite edges in the native render; the viewer's evidence panel already does this for acquaintance edges.
- Per-edge manual confirmation or denial of a single acquaintance, beyond the per-chat marker.
- Migrating the native app's Canvas render and sky onboarding view to the acquaintance presentation.
- Anonymized structure-only sharing.
- Incremental resync. Full rebuild is fast enough.

---

## Open questions

**Does `chat_handle_join` still list someone who left a group?**
Confirmed schema: `(chat_id, handle_id)` with a UNIQUE constraint and nothing else.
No dates, no status column, so the table cannot distinguish current from historical membership.
This matters more under the bipartite model because group membership *is* the edge.
That is acceptable here: roster is taken from `chat_handle_join` as historical truth, and liveness comes from message activity instead.

**How many of the 615 graph people lack a Contacts match?**
Sizes the model pass. Measure before building it.
