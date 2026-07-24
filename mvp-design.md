# Haven MVP Design

## What Haven is

Haven is a searchable private memory network for the people you know.

You save people, you connect with them through one central hub, and later you find any of them by any detail you remember.

The phone is the product.
You meet people holding your phone, so Haven is phone-first and the feel of the app matters as much as the features.

## The MVP in one sentence

An iPhone app where you have a profile, you connect with people in one tap, and every person you know becomes searchable by any detail you remember about them.

## Stack decisions (and why)

### Client: native SwiftUI

We build the client natively in SwiftUI rather than wrapping the web app.

Haven is a human and social app where the entire value is how it feels to hold, connect, and browse people.
Gesture physics, spring transitions, haptics, momentum scroll, and keyboard behavior are the product, not polish added later.
A WebView has a ceiling on that feel that native does not, so native is the right tool for what we care most about.

Development cost and speed are explicitly not the deciding factor here.
Long-term quality and the tactile experience win.

### Backend: Convex (kept)

We keep Convex as the backend.

Going native is a client rebuild, not a full-system rewrite.
The Convex data model, functions, and auth logic largely persist.
Convex ships a Swift client and Clerk ships an iOS SDK, so the native app talks to the same backend.

Those mobile SDKs are newer and less battle-tested than their web counterparts.
That is the one real cost of going native, and Phase 0 exists to de-risk it before we build anything real on top.

We change one foundation at a time.
Going native is already one big change, so we do not also swap the database at the same moment.

One caveat that shapes the client design: Convex is online-first and its Swift client has no durable offline write queue.
The capture moment happens at events with bad connectivity, so the client owns a small local pending queue (see The offline rule below).

### Auth: Clerk with custom UI

We use Clerk, with fully custom UI.

Clerk supports headless custom flows where we build every screen ourselves in SwiftUI and call Clerk methods underneath.
On iOS this is the normal path, so we get full control of the sign-in and sign-up feel while Clerk carries the security machinery.

We include Sign in with Apple from day one.
App Store guideline 4.8 requires it once any third-party login (for example Google) is offered, and it is also the lowest-friction option for the App Clip later.

We do not build our own auth system.
The hard parts of auth are invisible and dangerous: password hashing, session token rotation, OAuth, verification, rate limiting, and breach handling.
Getting any of those subtly wrong leaks user data, and Haven lives or dies on trust.

### Repo layout

Monorepo.
The iOS app lives in an `ios/` directory next to the existing `convex/` backend and `src/` web app.
The web app stays alive as the waitlist and marketing surface, not as a product client.

### Datastore note: Convex now, revisit later

Haven's long-term data shape is relational plus graph plus vector.
Attributes are relational, the connection network is a graph, and semantic memory search is vector.

That shape fits a Postgres-family system (for example plain managed Postgres with pgvector, or Polygres) better than a pure document store in the long run.

We do not adopt that now.
The MVP needs none of graph traversal or hybrid retrieval, Polygres specifically is a very young product to bet a foundation on, and we refuse to stack two risky rewrites at once.
When the graph and matching phase becomes real, we evaluate the datastore against actual requirements.
Managed Postgres plus pgvector is the safe pick, Polygres is the ambitious one, and the small three-table model keeps migration cheap if we ever move.

## Design principles

The core loop is Capture, Refine, Recall, Reach.
If those feel great, Haven works.
If they do not, no feature saves it.

In the MVP, each stroke of the loop has a concrete form:
Capture is connecting or manually saving a person.
Refine is opening a contact and editing its memory notes.
Recall is search.
Reach is tapping the preferred contact method.
The swipe review queue is the future upgrade of Refine, not its definition, so the MVP notes editor is a money screen and not an afterthought textbox.

Single-player value comes first.
The directory, manual save, and search are useful even if you are the only Haven user in the world, so we build that before the network layer.

Reduce friction at the moment of input.
Input is the hardest thing to get, so every capture step must be fast enough to not break a live conversation.

The offline rule: capture never fails.
Events have terrible network, so every capture action writes locally first and syncs when connectivity returns.
The UI shows pending state, never an error, at the moment of capture.

Feel is validated early, not last.
Phase 1 includes a hero-interaction spike built to the full quality bar, so we learn our SwiftUI ceiling in week two instead of after four phases of plumbing.

Protect the scope.
The vision is large, and every idea will try to pull us off the core, so the roadmap stays parked until the core is proven.

## Scope: what is in, what is out

In for MVP:

Your own profile and shareable card.
Connect with another Haven user in one tap (mutual, no request and accept dance, because the act of connecting in person is the consent).
Manually save a person who is not on Haven yet, including a photo.
A directory of everyone you know.
Memory notes on every contact, with a first-class editing experience.
Search by structured attribute filters plus keyword matching over notes.
A local pending queue so capture works offline.
Sign in with Apple alongside other login options.
In-app account deletion (required by App Store guideline 5.1.1).

Out for MVP, parked but not forgotten:

App Clip connect-back for non-users.
Semantic natural-language search.
The swipe review queue and voice capture (the upgrade of Refine).
LinkedIn scraping and enrichment.
Calendar smart-matching.
Selective card sharing (per-person control of which fields are revealed).
Rotating connect tokens (anti-replay).
Bluetooth radar and ambient detection.
Any social, matching, or feed layer.
The future idea of the system reading your messages to suggest people.

## Data model (Convex)

Three tables. This is the whole backend for MVP.

### profiles

A Haven user's own card, the canonical source of their data.
Fields: name, photo, handles (Instagram, X, LinkedIn, phone, each flagged verified when it came from an OAuth connection), the primary platform, structured attributes (city as name plus admin area plus country, company, role), and a unique `havenHandle` that the beacon URL resolves to.
The exact field list Phase 1 adds is in `phase1-build-plan.md`.

### contacts

Your directory.
Each row is one person you know, and it uses an overlay model.

A contact always stores your layer: memory notes, your own custom fields, and a photo you attached.
If the person is a connected Haven user, the contact also holds a reference to their live profile, and the app renders the merge of their canonical data plus your layer.
If the person is not on Haven, the contact stores their data directly: display name, structured attributes, social handles, preferred contact, photo.

Reference, not copy, for connection-backed contacts.
Copying at connect time would let contacts go stale, which is the exact problem Haven exists to solve.
With the overlay, their card stays current and your memories stay yours.

Search runs over this table (merged view for connection-backed rows).

### connections

Mutual edges between two Haven users.
When two users connect, one edge is created and a contact row appears in each person's directory referencing the other's profile.

### Deletion semantics

When a user deletes their account, their profile and canonical data are removed.
Contacts in other people's directories that referenced the deleted profile collapse to a frozen snapshot owned by the directory owner, like a phone contact.
Your memory of a person is yours, but the live canonical data belongs to them and leaves with them.

The model is deliberately small so it stays portable if we ever leave Convex.

## Screens (SwiftUI)

Onboarding: one welcome screen carrying Clerk sign-in (Sign in with Apple first), then three questions - name, city, and one way to reach you - then your card.
Photo is never asked; it arrives with an OAuth connection or later in edit.
Company and role live in the schema and on the edit screen, never in onboarding.
The screen-by-screen spec is in `phase1-build-plan.md`.

My Card: your profile as a card that you show people. Editable, and the surface where unfilled fields read as unlit stars.

Your beacon: your QR, resolving to `inhavens.com/<havenHandle>` rather than to any social profile.

Connect: start or accept a connection, and save a non-user manually.

Directory (home): the list of your contacts with search on top. Money screen one.

Contact detail with the notes editor: one person's attributes, socials, a tappable preferred-contact that opens straight into WhatsApp or IG or phone, and your memory notes with a first-class editing experience. Money screen two.

Add contact manually: for people not on Haven (name, photo, socials, notes).

Search: its own main screen alongside Directory, not a field buried on the directory list.
Filter chips for structured attributes (company, city, role) plus a keyword field over notes, and results.

## The search contract (MVP)

Be honest about what MVP search is, so testing measures scope and not a broken promise.

MVP search answers: filter by company, city, or role, combined with keywords that appear in your notes.
"Company: LinkedIn, city: SF" works.
Keyword "Spain shirt" works if those words are in the note.

MVP search does not answer natural-language sentences.
Typing "who do I know at LinkedIn who lives in SF" into a box is the semantic fast-follow, not v1.
Fuzzy matching is limited, so a misspelled name may not match.

The search UI is designed as filters plus keywords, so users are never invited to type a sentence that will return nothing.

## The connect flow (MVP version)

For v1 we support the both-have-Haven path only.

Two users connect in person, and both directories update mutually with each other's card.
No separate request and accept step, because connecting in person is the consent.

If the other person is not on Haven, you save them manually.
That manual save is the fallback floor.

Known hole, accepted consciously: a screenshot of a connect code works forever for anyone holding the image.
Fine at trusted-cohort scale.
Rotating tokens are the later fix and live on the roadmap.

The App Clip connect-back for non-users is the very next thing after v1.
It is not blocking, because the first small cohort can all be on Haven for testing.

## Core use cases (start to end)

The core loop is Capture, then Refine, then Recall, then Reach, wrapped by onboarding.

### A. Set up my card (onboarding, once)

I download Haven and sign in.
I build my card: photo, name, my handles, and I mark the one I actually want people to reach me on.
I add where I live, where I work, and my role.
Now I have a card I can show anyone, and I am findable by the people I connect with.

### B. Meet someone and capture them (Capture)

I am at an event and meet someone.
If they have Haven, we connect and their card lands in my directory instantly with all their details, no typing.
If they do not, I add them in a few seconds with a name, a handle, and a quick note.
Either way they are now in my directory, captured without breaking the conversation, even if the venue Wi-Fi is dead.

### C. Add context (Refine)

Later that night I open Haven, go to the person I met, and drop a memory into their notes: "met at Katrin, wore a Spain shirt, works on Amazon's research team, we talked soccer."
Thirty seconds, and the person is richly remembered instead of a blank name I will forget.

The future version of this step is the swipe queue: a stack of today's people, swipe left to skip, swipe right to keep and drop a voice or text memory.
The MVP version is the notes editor, which is why the notes editor has to be excellent.

### D. Find someone by what I remember (Recall)

Weeks later I need that person but I have forgotten their name.
I filter by company LinkedIn and city SF, or I search the keyword "Spain shirt."
Haven pulls them up.
This is the thing other apps cannot do, because they only search by name or a username that might have changed, while Haven searches by everything I know about a person.

The natural-language version of this ("who was the guy in the Spain shirt from Katrin") arrives with semantic search as the first fast-follow.

### E. Reach out (Reach)

I found them, and their card shows the contact method they actually want to be reached on.
I tap it and it opens straight into WhatsApp or IG or their number.
I never had to remember which platform they prefer or dig through five apps, because Haven centralized it.

Everything on the roadmap just makes one of these steps lower-friction or richer.

## Build order

We sequence so something useful exists as early as possible.
The directory, manual save, and search have single-player value, so we build that before the network.

### Phase 0, Foundations

Apple Developer account, Xcode and SwiftUI project in `ios/`, wire in the Convex Swift client and Clerk iOS SDK.

Definition of done, and it is strict: sign in with Clerk on a physical iPhone, call an authenticated Convex query with the Clerk-issued token, and see a live update pushed to the screen.
Reading public data does not count.
The authenticated seam is the riskiest integration in the whole plan, and Phase 0 exists to prove it end to end.

Also in Phase 0: verify App Store name availability for "Haven" (the name is crowded, and a "Haven: ..." subtitle form may be needed).

### Phase 1, Profile plus the hero spike

Onboarding, create and edit profile, My Card.

Plus the hero-interaction spike: one moment built to the full quality bar with real springs, haptics, and gesture physics.
This validates our SwiftUI ceiling early and sets the standard everything else inherits.
The moment is the card reveal at the end of onboarding, the person's constellation completing and settling, because Phase 1 ships that screen anyway and it is what a person holds up to someone forever after.

`phase1-build-plan.md` is the implementation document for this phase and owns every Phase 1 detail: screen specs, design tokens, the Convex schema additions, the per-platform contact contracts, and the milestone order.
Where it and this document disagree on a Phase 1 decision, the build plan wins.
It also adds four things beyond the original scope here, each a deliberate decision rather than drift: the Haven handle plus beacon URL, the Lock Screen widget and its explainer, a public web card page at `inhavens.com/<handle>`, and Search as a separate main screen (a shell in Phase 1, wired in Phase 3).

### Phase 2, Directory, manual save, contact detail

Now you can save and open people, and the app is dogfoodable immediately.
The local pending queue ships here, because capture must never fail offline.
The notes editor ships here and gets money-screen treatment.
Prototype the contacts data model before building this phase (see todo.md, Prototype checkpoints).

### Phase 3, Search

Filter chips plus keyword search over the directory, per the search contract above.

### Phase 4, Connect

Connect two Haven users with an auto mutual connection, turning a private notebook into a network.

### Phase 5, Polish pass

Haptics, transitions, and gesture physics across every screen, extending the hero-spike standard to the whole app.
For Haven this is the product, so it gets its own real phase, not leftover time.

### Phase 6, Distribution

TestFlight to the waitlist cohort first, then App Store submission.
Submission needs the compliance checklist below done.

## Prototype checkpoints

The spots worth a throwaway prototype, and the rule for when, are tracked in todo.md under "Prototype checkpoints".
In short: the contacts overlay, connection, and deletion data model is the one high-value prototype, done right before Phase 2; a couple of roadmap items (calendar matching, swipe queue) get one when built.
UI and feel questions go through SwiftUI previews in Xcode, not the web prototype skill.

## App Store compliance checklist

In-app account deletion (guideline 5.1.1), wired to the deletion semantics above.
Sign in with Apple offered alongside any third-party login (guideline 4.8).
Privacy policy URL and App Privacy nutrition labels.
Permission strings for camera (connect scanning) and photo library (contact photos).

## Testing strategy

Convex functions keep the existing vitest TDD flow: write the failing test, implement, run the suite.
The Swift side gets view-model unit tests for logic (search filtering, pending queue, merge rendering of overlay contacts).
UI feel is verified by hand on device, because springs and haptics cannot be asserted in a unit test, but everything with logic in it is test-first.

## Roadmap (fast-follows and later)

In rough order after MVP.

Semantic natural-language search, the AI-directory magic, using Convex vector search over memory notes.

App Clip connect-back, so a non-user can join the connection in the moment with a single Sign in with Apple tap, without an install wall.

The swipe review queue with voice capture, upgrading Refine from the notes editor to a thirty-second nightly ritual.

LinkedIn enrichment, where you paste a profile link and Haven scrapes it into structured, searchable data.

Calendar smart-matching, where the time you connected with someone plus your calendar pre-fills "met at X" for you to confirm or edit.

Selective card sharing, per-person control over which fields a connection reveals, because all-or-nothing sharing will be an early user ask.

Rotating connect tokens, closing the screenshot-replay hole.

Bluetooth radar as an explicit foreground event mode, and only later a wearable beacon if demand proves out.

The social and matching layer, opt-in and machine-only, where shared interests surface abstract matches without exposing the underlying data.

The far-future idea of the system reading your messages to suggest people, noted only so we do not lose it.

## Concerns

These are the unsolved friction problems at the heart of the product.
They are mostly behavioral and psychological, not technical, which is what makes them hard.
None of them are blockers, but they are the things most likely to decide whether Haven actually works.

### 1. Friction to manually add people

Manual entry is slow relative to a live conversation.
It is framed as the fallback floor, but until the App Clip ships it is the default path at real events, because most strangers will not have Haven.
So the piece we treated as an edge case carries most of the early capture load, and if it feels like data entry people will not do it mid-conversation.
The open question is how fast and low-effort we can make manual add, and whether there is a lighter in-the-moment gesture than filling a form.

### 2. Friction to manually add dynamic context

Dynamic context is the memory only a human holds: how you think about someone, why they matter, the detail you would forget.
There is probably no machine shortcut here, because no scrape or API can know what is in your head, so this input is inherently manual.
That means the lever is not technical, it is psychological: how do we trigger the moment, and how do we make putting it in feel frictionless or even rewarding rather than like a chore.
Direction worth exploring: the right timing of the prompt, making the act feel like a small reward, and the lightest possible input (a sentence, a voice note) instead of structured fields.
This is an open design problem, not a solved one.

### 3. Swipe-to-approve context assumes re-engagement that may not happen

The swipe review ritual assumes people open the app later, on the couch, to process the day.
Many will not.
Deferred review depends on re-engagement that we cannot count on, so the whole "nightly ritual" model may be fragile.
The open question is whether context should be captured more in the moment instead of deferred, or whether a well-timed reminder can reliably pull people back, and this is exactly why the swipe queue is a fast-follow to test rather than an MVP assumption.

## Open questions and risks

The Convex Swift client and Clerk iOS SDK are newer than their web versions.
This is the main technical risk, mitigated by Phase 0's strict definition of done.

WebView was rejected precisely because of gesture feel, so native quality is now on us to deliver, starting with the Phase 1 hero spike rather than waiting for Phase 5.

Real-world validation has a cold-start trap: at actual events, strangers will not have Haven, so most capture falls to manual entry until the App Clip ships.
Judge the MVP on single-player value (do testers return to search their directory), not on network effects it cannot have yet.

The datastore may need to move to a Postgres-family system when the graph and matching phase arrives, and we accept re-evaluating it then rather than now.
