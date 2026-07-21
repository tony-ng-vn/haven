# Facebook Integration Research

Date: 2026-07-20
Status: Research / recommendation
Audience: Product + engineering decision on whether and how Euno should integrate with Facebook (Meta)

## Verdict

**Do not build a Facebook data/API integration for importing friends or enriching other people's profiles.**
Meta locked down general friend-graph access after the 2018 Cambridge Analytica fallout, and what remains is both nearly useless for this purpose and a worse product fit than the LinkedIn case already rejected.

**Do keep treating Facebook as a first-class capture source** (already done).
Facebook has the exact same platform-enum and link-derivation treatment as LinkedIn in the codebase today, so no new engineering is needed there.

**There is no meaningful "optional later" here**, unlike LinkedIn's Sign In option.
Facebook Login via Clerk exists as a generic auth choice but does not unlock any of the friend-import behavior people actually ask for, so it does not change the verdict on this question.

---

## What Euno already does with Facebook

Facebook is already in the product surface, without any Facebook API:

| Surface | Behavior today |
| --- | --- |
| Screenshot capture | `convex/openaiClient.ts` lists `facebook` in the same `PLATFORMS` enum as `linkedin`; vision extraction pulls name / handle / headline / bio when visible, identical treatment to every other platform. |
| Profile URL derivation | `deriveProfileUrl("facebook", ...)` returns `null`. Comment in `src/lib.ts` names Facebook explicitly: "LinkedIn and Facebook use slugs that never appear in a profile screenshot," so they cannot be derived from a handle the way `x`, `instagram`, `github`, `tiktok`, `threads`, and `bluesky` can. |
| Triage UI | `src/CaptureTriage.tsx` maps `facebook` to the label "Facebook" in `PLATFORM_LABELS`, same list as `linkedin`. When no URL can be derived, CaptureTriage shows the optional "Their profile link" field, and `normalizeUrl` accepts a bare pasted domain. |
| Person record | Optional `link` stores whatever the user pastes (often a Facebook profile URL). |
| Auth | Clerk; Facebook Login is a possible dashboard-enabled OAuth provider but is not called out or enabled in-app today. |

MVP design already called bulk import (Apple Contacts) explicitly out of scope, and the LinkedIn research doc reached the same conclusion for LinkedIn connections.
A Facebook friends import is the same class of feature, aimed at the same "seed my people list" impulse, and evaluated below on the same terms.

---

## Integration options evaluated

### 1. Import the user's Facebook friends list (Graph API)

**What people usually mean:** "Connect Facebook -> seed my people list."

**API reality (2026):** The Graph API's `user/friends` edge and `user_friends` permission are still present in the current API version (v25.0 at time of writing), but their behavior has not changed since the 2018 lockdown.
Meta's own reference page states the edge "will only return any friends who have used (via Facebook Login) the app making the request," and adds that "if a friend of the person declines the `user_friends` permission, that friend will not show up in the friend list for this person."
In practice this means: only the subset of a user's friends who (a) have also installed/logged into Euno via Facebook Login, and (b) have themselves granted `user_friends` to Euno.
For a new consumer app with a small user base, that subset rounds to zero for the overwhelming majority of users at every stage before Euno has meaningful adoption among a person's actual friends.
This is not a paperwork gate that approval fixes; it is Meta's actual response payload, unconditionally, for every app.

**Product fit:** Poor, and poor for a different reason than LinkedIn's partner-gating - here the mechanism is fundamentally self-defeating (it only works once most of a user's friends already use Euno, at which point the import solves a problem that no longer exists).

- PRODUCT.md: private memory layer; explicitly "not a social network," no feeds, no friend/follower mechanics.
- MVP design doc: bulk import (Apple Contacts) is out of scope; the same reasoning applies here.
- A friends import with no "how we met" context is exactly the empty social-media catalog Euno exists to replace.

**Recommendation:** Skip.
There is no partner-approval path that changes this: the mutual-opt-in constraint is the current, intended, and stable design of the permission, not a temporary restriction.

### 2. Enrich a person from a pasted Facebook profile URL

**What people usually mean:** User pastes `facebook.com/someone` -> Euno fills name, photo, or details automatically.

**API reality:** There is no Graph API path for looking up an arbitrary other person's profile for a general third-party app.
`public_profile` (the default, pre-approved permission) returns only `id` and `name`, and only for the person who is currently authenticated into the app themselves - not for an arbitrary profile URL a user happens to paste in.
Personal profile data and the friend graph for non-consenting third parties have been off-limits to general developer apps since Meta's 2015 platform changes, tightened further in 2018.

**Scraping / third-party data brokers:** Meta's Platform Terms explicitly prohibit automated data collection ("harvesting bots, robots, spiders, or scrapers") without separate written permission, and prohibit transferring collected data to third parties.
This is the same ToS-hostile territory the LinkedIn doc ruled out for Proxycurl-style scraping, and Facebook's enforcement posture (including active litigation against scraping operations) is at least as aggressive.

**Recommendation:** Do not build, do not scrape.
Keep the existing model: the user (or screenshot OCR) supplies the memory; a pasted link is a door out, not a data source in.

### 3. Export your own friends list via Facebook's data export (Download Your Information)

**What people usually mean:** Same goal as option 1, reached through the self-service export every Facebook user already has instead of an API.

**How it works today:** Facebook's "Download Your Information" tool (Settings > Your Facebook Information, or via Meta's Accounts Center) lets any user request an export of their own account data, with "Friends and followers" listed as one of the "Connections" categories.
Users can choose HTML (viewable in a browser) or JSON (machine-readable) format, and export to a local device or to a linked external service.
The friends data lands in a `friends_and_followers/friends.json` file inside the archive, containing each friend's name and a timestamp (when the connection was made) - no email address, phone number, or other contact detail is included, since Facebook does not export a friend's private contact information through this path, only what the exporting user themselves can already see (names and connection dates).

**Feasibility:** Fully feasible and legal, right now, with zero Meta involvement on Euno's side, exactly analogous to the LinkedIn CSV export option.
It needs no developer app, no permission review, no ToS exposure, since the user is exporting their own data through Meta's own privacy tooling; Euno would only need to accept a JSON upload.
But the ceiling is lower than LinkedIn's CSV: LinkedIn's export at least sometimes carries company/position/connected-on fields alongside a name; Facebook's friends export is closer to a bare name list with a date, and structurally cannot carry any "how you met" context, professional detail, or even a reliable way to contact the person.

**Product fit:** Weaker than the already-rejected LinkedIn CSV option, for the same underlying reason plus one more:

- PRODUCT.md: private memory layer; anti-CRM, anti-social-network by design.
- MVP design doc: bulk import explicitly out of MVP scope.
- Facebook friends are, definitionally, a pure social graph with no professional or "how we met" framing at all - even less contextual than a LinkedIn connection (which at least often implies a work or event context via title/company).
A raw name-and-date list is the empty catalog Euno is built to replace, more purely than LinkedIn's connections list is.

**Recommendation:** Not now, and with less of an opening than LinkedIn's equivalent.
If product ever deliberately revisits Contacts-style seeding, this export (not the Graph API) would be the technically viable route, but the content it carries (name + date only) makes it a weaker seed than LinkedIn's export, let alone Apple Contacts.

### 4. Sign in / continue with Facebook (Login)

**What it is:** Auth only - name, email, and profile photo of the signed-in user, via Facebook Login.

**Effort:** Dashboard config for Clerk's Facebook OAuth connection; requires a Meta developer app in Live mode with `public_profile` and `email` permissions (both pre-approved, no review needed for these two).

**Product fit:** Neutral, same as LinkedIn OIDC.
Helps conversion for people who already trust Facebook as an identity provider; does not touch the friend graph or recall loop at all.

**Recommendation:** Optional growth/auth experiment only, no different in kind from the LinkedIn OIDC option already rated "optional later."
Not required for any Facebook-flavored product value, since there isn't Facebook-flavored product value beyond auth.

### 5. Post / share to Facebook

Out of scope for Euno's one job (hand back a person so you can reach out yourself, not broadcast anything).
Skip, same as the LinkedIn posting scope call.

### 6. Deepen Facebook-aware capture (no Facebook API)

**This is the only Facebook-shaped work worth doing**, and it is already essentially done.

Facebook already gets identical treatment to LinkedIn everywhere in the codebase: same `PLATFORMS` enum entry, same "cannot derive URL from handle" comment and code path, same `PLATFORM_LABELS` entry, same triage fallback to a pasted link.
The one gap that exists for LinkedIn - a platform-specific placeholder/helper copy nudging users to paste the link because it is not visible in the screenshot - would apply equally to Facebook if and when that LinkedIn-specific P0 change ships, since the underlying reason (vanity-slug URLs invisible in-screenshot) is identical for both platforms.

**Recommended product move:** When the LinkedIn-specific link-paste copy improvement (from the LinkedIn research doc) is implemented, extend the same platform-aware placeholder/helper text to `platform === "facebook"` at the same time, since the code path and the underlying UX gap are shared.
No new work item is needed beyond folding Facebook into that existing LinkedIn ticket.

---

## Fit against Euno principles

| Principle | Facebook friends/API import | Facebook friends export (JSON) | Capture + paste link |
| --- | --- | --- | --- |
| Hand back the person, not a dashboard | Fails - would dump a raw social graph, and a near-empty one at that | Fails - bare name + date list, no context at all | Passes |
| No CRM / scoring | Passes (not CRM-shaped) but still a bulk-import antipattern | Same | Passes |
| Private, user-authored memory | Contested - friend graph is Meta's structure, not the user's memory | Contested, same reason, weaker content | Passes |
| MVP "link + context" loop | Overbuilds, and delivers almost nothing given the mutual-opt-in limit | Overbuilds; delivers a name list with no "why this person matters" | Extends existing loop |

---

## Decision matrix

| Option | Feasible without partnership? | Product fit | Recommend |
| --- | --- | --- | --- |
| Friends import (Graph API, `user_friends`) | Yes, but returns almost nothing (mutual app-adoption required) | Weak | No |
| Friends export (JSON, user-initiated) | Yes | Weak, weaker than LinkedIn's equivalent | No |
| URL -> profile enrich via API | No (no such API exists for third parties) | Weak / not applicable | No |
| Scraping / third-party Facebook data | Technically yes, ToS/legal no | Weak | No |
| Continue with Facebook (Login) | Yes | Auth only | Optional later |
| Facebook-aware capture UX | Yes | Strong (already implemented) | **Yes - already done; fold into LinkedIn's link-paste ticket** |

---

## Suggested next step

No new engineering initiative for Facebook specifically.
When the LinkedIn capture-triage link-paste improvement ships, add `facebook` to the same platform-aware copy change, since the codebase already treats both platforms identically and the UX gap (vanity URL invisible on screen) is the same for both.
Treat any future "Connect Facebook" marketing language as **auth only**, never as **import**, since the friend-graph APIs cannot deliver a usable import regardless of approval status.

## Sources

- [Permissions Reference for Meta Technologies APIs: user_friends](https://developers.facebook.com/docs/permissions/reference/user_friends/) - permission description: "get a list of a person's friends using that app"
- [Graph API Reference: User Friends edge](https://developers.facebook.com/docs/graph-api/reference/user/friends/) - current-version (v25.0) behavior: "will only return any friends who have used (via Facebook Login) the app making the request," and a declining friend "will not show up in the friend list"
- [Facebook Help Center: Export a copy of your Facebook information](https://www.facebook.com/help/212802592074644) - HTML vs JSON export formats, export to device or external service
- [Facebook Help Center: Access and download your information](https://www.facebook.com/help/1701730696756992)
- [Facebook Help Center: Learn what categories of information are available to export](https://www.facebook.com/help/930396167085762) - "Connections" category includes "friends and followers"
- [Meta Platform Terms for Developers](https://developers.facebook.com/terms/dfc_platform_terms/) - automated data collection and third-party data transfer prohibitions
- In-repo: `PRODUCT.md`, `docs/superpowers/specs/2026-07-15-euno-mvp-design.md`, `docs/superpowers/specs/2026-07-20-linkedin-integration-research.md`, `src/lib.ts`, `convex/openaiClient.ts`, `src/CaptureTriage.tsx`
