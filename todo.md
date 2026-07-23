# Haven - TODO and backlog

Living work tracker.
The stable design and architecture live in `mvp-design.md`; this file tracks state: what is done, in progress, and queued.

Checkbox convention: `[ ]` not started, `[~]` in progress, `[x]` done.

## Now / next

- [ ] Phase 1: Profile. Onboarding, create and edit profile, My Card. Plus the hero-interaction spike (one moment built to the full quality bar) to validate the SwiftUI feel early.
- [ ] Housekeeping: pull `main` into the working checkout, then remove the leftover `.worktrees/feat-ios-foundations` worktree and its branch so there is one copy.

## MVP backlog (in order)

- [ ] Phase 2: Directory + manual save + contact detail + notes editor. Local pending queue so capture never fails offline.
- [ ] Phase 3: Search. Filter chips (company / city / role) plus keyword over notes. See the search contract in `mvp-design.md`.
- [ ] Phase 4: Connect. Mutual auto-connect between two Haven users.
- [ ] Phase 5: Polish pass. Haptics, transitions, gesture physics across the app.
- [ ] Phase 6: Distribution. TestFlight to the waitlist cohort, then App Store.
  - [ ] Go through the full iOS App Launch Checklist before submitting (Cole Caccamise): https://colecaccamise.notion.site/The-iOS-App-Launch-Checklist-3786e16e7a578019a96ac84819de934a
  - [ ] App Store compliance basics are already listed in `mvp-design.md` (in-app account deletion, Sign in with Apple, privacy labels, permission strings).

## Prototype checkpoints

These are LOGIC prototypes (a tiny hand-driven terminal app over the pure logic), done at the phase noted, not before.
Rule: prototype when guessing wrong is costly and hard to undo; skip when the answer is clear or cheap to reverse.
UI and feel questions go through SwiftUI previews in Xcode, not the web-oriented prototype skill.

- [ ] Before Phase 2 - contacts data model. HIGH value.
  Q: does the overlay model hold up (a contact is either a reference to a live Haven profile merged with your private layer, or a standalone manual entry), what happens on connect (both sides populate), and what happens on account deletion (the contact collapses to a frozen snapshot you own)?
  Why: getting it wrong unwinds the Convex schema and the SwiftUI screens at the same time.
- [ ] Roadmap - calendar smart-matching heuristic (when we build it).
  Q: does "connection time + your calendar event at that time -> pre-filled met at X" behave across back-to-back, all-day, no-event, and overlapping cases?
- [ ] Roadmap - swipe review queue state model (when we build it).
  Q: how does a contact move pending -> kept or skipped, and how does dwell-time grouping decide who you actually talked to? (The swipe feel itself is an Xcode question.)

## Roadmap (post-MVP, parked)

- [ ] App Clip connect-back: a non-user joins the connection in the moment with one Sign-in-with-Apple tap, no install wall.
- [ ] Semantic / natural-language search over memories (Convex vector search).
- [ ] Swipe review queue + voice capture (the upgrade of Refine).
- [ ] LinkedIn enrichment: paste a profile link, scrape it into searchable data.
- [ ] Calendar smart-matching: pre-fill "met at X" from connection time + calendar.
- [ ] Selective card sharing: per-person control over which fields a connection reveals.
- [ ] Rotating connect tokens: close the screenshot-replay hole.
- [ ] Bluetooth radar: foreground event mode first; wearable beacon only if demand proves out.
- [ ] Social / matching layer: opt-in, machine-only, abstract matches without exposing the underlying data.
- [ ] v4 idea: the system reads your messages to suggest people (noted only so we do not lose it).

## Done

- [x] MVP design doc - `mvp-design.md` (PR #49).
- [x] Phase 0: iOS foundations. Native SwiftUI app; the Clerk -> Convex auth seam is verified working on a signed simulator build. Two fixes were needed: the convex-templated Clerk token and the keychain-access-groups entitlement (PR #52). Scaffold in PR #50, config keys in PR #51.
