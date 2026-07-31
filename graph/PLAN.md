# Connection graph: product plan

Status: design settled, nothing built.
Date: 2026-07-31.
Location: `graph/` inside the euno-app repo. Separate product from Haven, shares no code with it.
Product name: TBD.

This is a **personal tool**, built by its only user, for that user, never distributed.
That single fact removes most of the constraints that would otherwise dominate this document.

Platform research behind the hard constraints: `docs/2026-07-30-imessage-connection-graph-research.md`.

---

## What this is

A macOS app that reads your own iMessage history and Contacts, and draws the graph of everyone you know and how they connect to each other.

The graph is the product.

It answers two questions:

1. Who connects to me.
2. Who in my network connects to each other.

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
When the roster is exactly the user plus one other person, it renders as a one-to-one edge, not a group node.
The 74-live-group projection was computed before this reclassification, so any 2-member rows inside the 74 shift from group nodes to one-to-one edges; the exact split is measured at build time.
A synthetic fixture must cover this shape.

---

## Edges

**One-to-one threads produce a direct person-to-person edge.**

**Group chats do not.**
The user connects to the group node, each member connects to the group node, and members are not connected to each other.

This bipartite model is chosen deliberately.
It costs 513 edges instead of many thousands, and it tells the truth: these people share a context, which is known, rather than these people know each other, which is not.
The relationship remains visible as two nodes hanging off a shared neighbor.
It is simply not a line.

**One line per pair**, however many reasons underlie it.

**Every edge carries a source field** from the first commit, so adding call history later is a new ingest path rather than a reshape.

Reason and strength are computed and stored on every edge.
Strength is required whether or not it is displayed, because it decides which edges survive pruning.

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

Force-directed layout.

Clustering needs no community detection.
It falls out of the bipartite structure: people are pulled toward the groups they belong to, so college friends bunch around the college thread and coworkers around the work thread.

The user is drawn as a node, but the user's edges are excluded from the force simulation and from the rest-state render.
Roughly 300 one-to-one edges plus 74 group memberships, close to half of all edges in the graph, terminate at the user.
Rendered and simulated, they make the user a giant hub whose springs pull every cluster toward center, destroying exactly the cluster separation the layout exists to show, and node-size-by-degree would make the user the largest object on screen.
The user's edges appear when the user's node is focused.
"Who connects to me" is answered by presence in the graph plus focus mode, not by permanent lines.

**First run animates the assembly.**
Nodes fly in, the simulation settles over several seconds, then rests.
This is not only spectacle: watching clusters separate teaches the viewer how to read the layout, which a static render cannot.

At rest, roughly the forty most connected nodes carry labels; everything else labels on zoom.
This is what keeps ~690 nodes reading as dense-but-organized rather than as noise.

Node size scales with connection count, except the user's node. Tunable.
Node color distinguishes people from groups. Tunable.

---

## Stack

Swift and SwiftUI, native rendering, no web view.
Rendering ~690 nodes with Canvas is comfortable, Contacts access is native, and the test expectations in `graph/GOAL.md` already assume a Swift test target.

---

## Interaction

In scope, because this is a tool used over time rather than a one-shot artifact.

- Click a node to focus it: highlight its neighborhood, dim everything else. Focusing your own node reveals your direct edges.
- Filter by time, so the graph can show a chosen period rather than all history.
- Toggle dead groups on and off.
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
- Displaying edge reason and strength.
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
