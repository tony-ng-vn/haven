# Phase 1 build plan: onboarding, card, and the two home screens

This is the handoff document for building Phase 1 of the Haven iOS app.
It is the result of the design prototyping rounds on 2026-07-23 and 2026-07-24, reviewed against `mvp-design.md`.
The visual source of truth is the interactive prototype at `design/onboarding-prototype.html` (open it in a browser and walk every screen before writing code).
`mvp-design.md` still owns the architecture and the phase sequence; where this document and the prototype changed a Phase 1 decision, this document wins and lists the change explicitly.

## What Phase 1 ships

A person installs Haven, signs in, answers three questions, and gets their card.
After onboarding they land in an app with two main screens (Directory and Search, both mostly empty shells in this phase), an edit surface for their card with their QR on the back of it, and an optional Lock Screen widget.

The hero moment is the card reveal: the person's constellation completing and settling.
Per `mvp-design.md`, this is built first, to the full quality bar, to find the SwiftUI ceiling early.

## Decisions ratified during prototyping

These were argued through the prototype rounds and are settled.
Do not relitigate them during implementation.

1. Onboarding is three questions: name, location, contact.
   Photo is not asked during onboarding; it arrives via OAuth import or later in edit.
2. Sign-in and the mood screen are one screen.
   Wordmark, one tagline line, Continue with Apple as the primary button, other options behind a secondary control.
3. Contact collection is authorize-first.
   Platforms are LinkedIn, X, Instagram, and phone, in a "Connect an account" group plus an "Or type one" group.
   Tapping a social row starts an OAuth authorization; a paste-a-link field is never a platform's advertised action, only what a failed or limited attempt degrades to, with copy naming whose limit it is.
4. Exactly one primary contact is chosen at onboarding.
   More handles can be added in edit later; the card keeps a quiet "add another way to reach me" entry point.
5. The constellation is seeded from the Convex user id, not the name and not a birthday.
   Names collide, birthdays give only 366 skies, and the user id survives display-name edits.
   The generation math ports from `src/sky.ts` (FNV-1a hash into a seeded PRNG, majors placed with a minimum separation, figure connected with Prim's MST).
   No LLM is involved anywhere in the sky.
6. On the card reveal the figure renders complete, not half-dim.
   The dim-star nudge for missing fields moves to the My Card / edit screen, where unfilled fields read as unlit stars.
7. The card layout never covers the constellation.
   Figure owns the top, serif name below it, imported photo small and inline beside the name.
8. Serif (New York via `.fontDesign(.serif)`) is reserved for people's names only.
   Questions, buttons, labels, and all other UI use SF Pro.
   This single rule is what keeps the app from reading as a meditation app.
9. Location is a city-level picker backed by MKLocalSearchCompleter, storing structured city, admin area, and country.
   Never a street address, never a location permission request.
10. The QR resolves to a Haven-owned address, `inhavens.com/<handle>`, not to any social profile.
    Authorization proves identity but cannot construct social profile links in the general case (LinkedIn's OIDC subject is pairwise app-scoped; X's username read sits behind paid tiers; Instagram is Professional-accounts-only).
    A social handle is content on the destination, not the destination.
11. The QR is named "Your beacon" ("Your tag" is the approved fallback name if beacon tests poorly).
12. The Lock Screen widget cannot be auto-added; iOS has no API for it.
    The widget pitch is a dismissible card on the Directory empty state, opening a mostly-visual explainer (a Lock Screen mockup picture, minimal words), never a wall in onboarding.
13. Search is a main screen alongside Directory, not a field buried on the directory list.
14. Progress through onboarding is shown with a thin stepper; light responds only to committed values, never keystrokes; nothing celebrates (no confetti, badges, streaks, or progress percentages).

## Corrections to make relative to the prototype

The prototype is the visual truth but it cheats in places a shipped app cannot.

- Star slots must be fixed per field, decided once: name 0, city 1, primary contact 2, photo 3, company 4, role 5.
  The prototype lights stars by count, which would reshuffle meaning as fields change.
  Fixed mapping is what makes the edit screen's unlit stars legible.
- The contact step gets a "Skip for now" ghost button.
  The prototype hard-requires a contact; the plan keeps name as the only truly required field.
  Skipping leaves the contact star unlit on My Card, which is the entire nudge.
- The city picker needs an escape hatch when the completer returns nothing (accept the raw typed city as unstructured fallback rather than forcing skip).
- The OAuth round trip is simulated with a timer and fixed demo handles in the prototype.
  The real flow runs through Clerk external accounts and returns real data; see the contact section below for the per-platform contract.
- The QR in the prototype is decorative; ship a real QR via CoreImage (CIQRCodeGenerator, error correction level M or better, boosted screen brightness while visible).
- The Directory empty-state copy must not promise scanning yet ("Scan someone's code" is Phase 4); Phase 1 copy pitches the beacon and the widget only.
- The prototype's semantic search ("Understood: people who are...") is a faked preview of the post-MVP fast-follow.
  Phase 3 ships the literal contract from `mvp-design.md` (filter chips plus keyword); keep the interp line's visual slot reserved but build none of it now.
- Onboarding needs real failure states the prototype omits: a mutation retry path when the network drops mid-onboarding, a loading state on Continue, and a resume path if the app is killed between sign-in and card completion (persist onboarding progress locally, resume at the first unanswered question).
- Email is not a platform.
  Earlier revisions of the prototype offered it in the "Or type one" group; that path is gone from both the prototype and the schema enum, and nothing should reintroduce it.

## Screen specs

Every screen uses one skeleton: header content pinned top, interactive content centered in the remaining space, actions pinned bottom.
All screens honor Dynamic Type, VoiceOver labels, and Reduce Motion (instant state changes instead of animations).

### 0. Welcome

Wordmark "Haven", tagline "Everyone you meet, findable later."
Primary: Continue with Apple (App Store guideline 4.8 requires Apple first once any third-party login exists).
Secondary ghost: other sign-in options (opens Clerk custom flow options).
Sky: ambient dust only, no figure.
Legal: privacy policy and terms links, small, bottom.

### 1. Name (required)

"What is your name?", one field (textContentType .name, autocapitalization .words), Continue disabled until non-empty.
On commit: profile name saved, constellation minted from user id, first star lights.

### 2. Location (skippable)

"Where are you based?" with hint "City only. Never your street address."
Typeahead over MKLocalSearchCompleter, suggestions as rows (city bold, region small), tap to select.
Selection commits the structured value and lights the city star.
Skip for now as ghost.

### 3. Contact (skippable, strongly encouraged)

"How should people reach you?" with hint "Connect an account and we fill in the rest. We never post."
Group one, Connect an account: Instagram, X, LinkedIn rows with brand glyphs and a Connect action.
Group two, Or type one: Phone row.
Per-platform contract:

- X: OAuth via Clerk external account; the returned external account includes the username; row completes with handle and check, nothing else appears.
- LinkedIn: OAuth verifies the person and returns name and photo but never the vanity URL; show a confirm panel, prefilled with a best-guess slug, copy "Connected as <name>. LinkedIn verifies you but never sends your profile address, so check this is right."
- Instagram: no personal-account API (Basic Display shut down 2024-12-04; the replacement covers Creator and Business accounts only).
  Attempt first; on the personal-account case degrade to a paste field with copy "Instagram only shares profiles for Creator and Business accounts. Paste your link and we will pull the handle out of it."
  A pasted profile URL is reduced to the handle with a regex; show a live link preview under the field.
- Phone: typed, phone keyboard, region-default country code, format and validate with PhoneNumberKit.

Selected platform shows a Primary tag.
Every successful OAuth also imports the profile photo (this replaces the photo question).
Continue disabled until a contact commits; Skip for now available.

### 4. Your card (the reveal, hero moment)

The complete figure settles at the top (scale 1.03 to 1.0, roughly 1100ms on a strong ease-out, with haptic), serif name beneath, city line, primary contact chip, small inline photo if imported.
Primary: "This is me" (advances to Directory).
Ghost: "Add another way to reach me" (opens edit).
This screen is milestone 1 and gets built first against hardcoded data.

### 5. Directory (home, empty shell in Phase 1)

Nav "People" with a count, search field (visual only in Phase 1, focusing it switches to the Search screen), honest empty state ("No one saved yet"), the dismissible Lock Screen widget promo card, and an Add someone button that is disabled or hidden until Phase 2.

### 6. Search (shell in Phase 1)

Search field, filter chip row, results list with serif names and matched-fragment highlighting.
Phase 1 ships the layout with the empty state only; wiring arrives in Phase 3 per the search contract.

The chips are company, city, and role, which is the canonical set from the search contract in `mvp-design.md`.
The prototype instead shows city, month, and context, and that difference is not a mistake to copy: month and context describe when and where you met someone, which lives on the `contacts` table that Phase 2 creates.
Those two are strong Phase 3 candidates once that data exists, but Phase 1 renders chips only for fields that are real.

### 7. My Card / edit

The card plus every field, filled or empty.
Empty fields render as unlit stars (fixed slot mapping above).
Fields: name, photo, city, handles list with primary toggle, company, role.
Company and role exist here and in the schema now (Phase 3 filters on them) but are never asked in onboarding.
Tapping a field edits that field alone; no wizard re-run.
Account deletion entry point lives behind a settings row here (guideline 5.1.1; full flow can land in Phase 6 but the row and the Convex mutation should exist early).

### 8. Lock Screen explainer

A picture, not a paragraph: a small Lock Screen mockup with the Haven widget under the clock, one line, "See what it opens" primary, "Not now" ghost.
The three-step how-to lives one tap deeper.

### 9. Your beacon, on the back of the card

Real QR encoding `https://inhavens.com/<handle>`, serif name, the address in mono under it, "Show this. Their camera lands on your card."
Boost brightness while visible.

Built as a screen of its own and folded into the card afterwards (2026-07-28).
It described the same object the card already was, so a separate screen meant two doors to one thing, and the one that skipped the card was the one people would learn.
Tap the card on My Card and it turns over.
`FeatureFlags.beaconEnabled` went with the screen: it kept the QR hidden in debug builds, where a code points at a site reading a different database, and a flag that hides the card's whole back is a feature nobody can develop.

## Design tokens

Palette (dark, committed; the app is dusk-only in Phase 1):

- Night `#0E1123` (ground)
- Dusk `#232A4D` (raised)
- Ember `#E8A87C` (horizon warmth)
- Star `#FFD9A0` (light, selection, primary accents)
- Ink `#F2EFE9` (text)
- Muted `#9DA3BE` (secondary text)
- Faint `#767C9C` (hints only; borderline contrast, never body text)
- Cream `#F2E7D5` on `#1A1730` (primary buttons)

Background: vertical gradient Night into Dusk with a restrained ember glow radiating from the bottom edge (atmosphere, not a reward; it does not swell with progress).
Type: SF Pro for all UI; New York serif strictly for person names (card, search results, beacon).
Motion: presses 140ms, screen transitions about 240ms on a strong ease-out (cubic-bezier 0.23, 1, 0.32, 1 equivalent spring), star ignition 800 to 900ms, reveal settle about 1100ms.
Haptics: light impact on commit (star ignition), medium on the card reveal, none elsewhere in onboarding.
Ambient dust: about 28 slow-drifting motes, deliberately dim, never competing with the person's stars; static under Reduce Motion.

## Backend work (Convex, test-first)

All changes are additive; the legacy web surface still calls `profiles.getMyProfile`, `setUsername`, and `meetExchange`, so nothing existing changes shape.
Keep the vitest TDD flow: failing test, implement, suite green, and replicate the Vercel check with `npx tsc -p convex/tsconfig.json --noEmit` before pushing.

Schema additions on `profiles` (all optional):

- `name: string`
- `photoStorageId: Id<"_storage">` (upload pattern already exists in `convex/captures.ts`)
- `city: { name, admin, country }` plus a normalized lowercase key for Phase 3 filtering (reuse the `normalizeName` approach in `convex/nameSearch.ts`)
- `handles: [{ platform: "instagram" | "x" | "linkedin" | "phone", value, verified: boolean }]`
  `verified` means the value itself was proven, not merely that an OAuth round trip happened.
  So X is verified (the external account carries the username) and LinkedIn is not (OAuth proves the person but the handle is a slug they confirmed by hand), which is the whole reason its confirm panel exists.
- `primaryPlatform` using the same platform union as `handles`, never a bare string, with one invariant enforced in the mutation: the primary platform must exist in the handle list, and deleting the primary handle clears it.
- `company: string`, `role: string` (edit-only fields)
- `havenHandle: string` (unique, indexed)

Before writing any of this, settle `havenHandle` against the `username` that `profiles` already has.
`convex/schema.ts` already carries a unique, indexed `username`, and `convex/profiles.ts` already claims it idempotently in `setUsername` for the legacy meet-exchange flow.
Two unique handles on one row, one resolving the beacon URL and one owned by dead web code, is a trap: nothing tells you which one the QR encodes, and they will drift.
Recommendation: reuse `username` as the beacon handle and add `claimHandle` alongside `setUsername` rather than replacing it, after checking that `validateUsername`'s rules are safe in a URL path.
`claimHandle` gets the new behavior (the suggestion ladder, a returned status instead of a throw) and `setUsername` keeps its exact current signature until the legacy web meet-exchange flow is either deleted or moved over.
Both write the same field, so there is no migration and no backfill; what would break the web app is changing `setUsername`, not adding a sibling to it.
Retiring `setUsername` is a separate decision that belongs with the orphaned-web-surface call in `todo.md`.
This is open question 5 below.

Functions:

- `profiles.updateMyProfile` partial update mutation.
- `profiles.claimHandle` idempotent per the repo convention: check and insert in one mutation, return `{ status: "claimed" | "taken" }`, key on the handle itself.
  Suggest `firstname` first, then `firstname-lastname`, then a short numeric suffix.
- `profiles.getByHandle` public query for the future web card page (must never return phone or email; see privacy below).

## iOS implementation notes

- Auth: Clerk custom SwiftUI flows, Sign in with Apple first.
  The Phase 0 gotchas are already proven: the Convex JWT template token and the keychain-access-groups entitlement.
- OAuth connect: Clerk external-account linking, surfaced through ASWebAuthenticationSession.
  Spike this in day one of milestone 4; if the iOS SDK surface for linking is incomplete, the fallback is a short authenticated web round trip to Clerk's hosted linking page.
- City picker: MKLocalSearchCompleter constrained to city-level results (verify the exact resultTypes/filter combination in a spike; iOS 18 adds address filtering).
- Phone: PhoneNumberKit for format and validation.
- QR: CIQRCodeGenerator.
- Widget: WidgetKit accessory family (accessoryCircular or accessoryRectangular), `widgetURL` deep link straight to My Card with the card already turned to the code.
- Deep links: register the `inhavens.com` universal link domain now (apple-app-site-association served from the Vercel app) so scanned beacons open the app when installed.
- Onboarding state: persist progress locally so a killed app resumes at the first unanswered question; every commit is one small Convex mutation with a retry-on-failure affordance, never a dead end.

## New scope this plan adds beyond mvp-design.md

Named explicitly so the scope change is a decision, not a drift.

1. Haven handle plus beacon URL (`inhavens.com/<handle>`).
   Required for the beacon to mean anything; the claim flow ships in Phase 1.
2. Lock Screen widget plus explainer screen.
   Small, self-contained, high leverage for the share loop.
3. Public web card page at `inhavens.com/<handle>` (web repo, not iOS).
   Minimum version: name, photo, constellation (reuse `src/sky.ts` and seed from the same user id), city, primary social handle, and a "Get Haven" link with a smart app banner.
   Privacy rule, non-negotiable: phone numbers and email are never rendered on the public page; if the primary contact is phone, the public page shows only a Connect call-to-action.
   This page can trail the iOS milestones by a week without blocking anything; until it shipped, the QR was hidden behind a feature flag.
4. Search as a separate main screen (shell now, wired in Phase 3).

## Build order (milestones, each with a definition of done)

1. Hero spike: card reveal with hardcoded profile, full quality bar (springs, haptic, Reduce Motion path).
   Done when it feels right on a physical device and the SwiftUI ceiling is judged sufficient.
2. Design system: color and type tokens, Field, PrimaryButton, GhostButton, Row, screen skeleton, dust layer, sky renderer ported from `src/sky.ts` with fixed slot mapping.
   Done when the welcome and name screens render pixel-faithful to the prototype.
3. Convex schema and functions, test-first, including `claimHandle`.
   Done when vitest and the convex tsc check are green and the legacy web smoke path still works.
4. Onboarding flow wired end to end: welcome, name, location, contact (all four platform paths), card reveal, with resume and retry states.
   Done when a fresh install on a physical iPhone reaches the card with airplane-mode interruptions handled.
5. My Card / edit with unlit-star states, company and role, handle management, photo add.
6. Directory and Search shells, widget promo card, Lock Screen explainer.
7. Beacon screen with real QR, handle claim UX, brightness boost (behind a flag until the web page exists).
8. Lock Screen widget and deep link.
9. Web card page in the existing web app (parallel track, can start any time after milestone 3).

## Out of scope for Phase 1

Contacts, notes editor, offline pending queue (Phase 2).
Search wiring (Phase 3).
Connect handshake and scanning (Phase 4).
Semantic search, App Clip, selective sharing, rotating tokens (roadmap).
Any Facebook or Snapchat integration (cut on 2026-07-24).

## Open questions for Tony

Each has a recommendation; answer before the relevant milestone, none block milestone 1.

1. Haven handle UX: auto-claim a suggestion during onboarding silently, or show a one-line "your address" confirm the first time the card is turned over?
   Recommendation: silent auto-claim at card creation, editable later in My Card; one less onboarding step.
2. Public page privacy defaults beyond the phone rule: should city show publicly?
   Recommendation: yes to city, no to company and role until selective sharing exists.
3. Directory and Search as two tabs, or one People screen whose search field expands?
   Recommendation: two tabs as prototyped; you asked for two main screens and the tab bar is where Phase 2 grows.
4. "Beacon" naming: keep, or fall back to "tag"?
   Recommendation: keep beacon; revisit only if cohort testing shows confusion.
5. `havenHandle` versus the existing `username` on `profiles`: reuse one field, or carry both?
   Recommendation: reuse `username` and leave `setUsername` untouched, per the schema section above.
   This one blocks milestone 3 rather than milestone 4, so answer it first.
6. The X username read: decision 10 notes that X's username API sits behind paid tiers, while the contact contract assumes Clerk's external account hands back the username at link time.
   Both hold only if Clerk's own app-tier access covers that read.
   Confirm in the day-one OAuth spike of milestone 4; if it does not, X degrades to the paste-a-link path like a personal Instagram account.

## On canvasui.dev

Reviewed 2026-07-24.
It is a web-only, WebGL, HTML-in-canvas effects library (React, Vue, Svelte, vanilla; MIT plus Commons Clause), so it is not usable in the SwiftUI app at all.
The one surface where it could apply is the public web card page or the marketing site.
Recommendation: do not adopt it for the card page; the page should render the person's actual constellation with the already-built `src/sky.ts`, which keeps identity coherent across app and web and adds zero dependencies.
If a marketing flourish is ever wanted on the waitlist page, its Glass or Particle effects are the ones consistent with the dusk language; treat that as optional polish, never product.

## Acceptance for the phase

- Fresh install to card on a physical iPhone in under sixty seconds without typing anything except a name (and three letters of a city).
  Measure only Haven's own screens: start the clock when the welcome screen appears and stop it at the card.
  Time spent inside system-owned sheets (the Sign in with Apple prompt, an OAuth web session) does not count, because we do not control it.
  Run it on the happy path, connecting one account rather than skipping contact.
- Every onboarding interruption (kill, network loss, OAuth cancel) resumes without data loss or a dead end.
- Reduce Motion, VoiceOver, and Dynamic Type verified on every screen.
- vitest suite and convex typecheck green; legacy web app unaffected.
- The card reveal, judged on device, feels like the best moment in the app.
