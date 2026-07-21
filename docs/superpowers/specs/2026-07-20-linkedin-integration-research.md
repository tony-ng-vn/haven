# LinkedIn Integration Research

Date: 2026-07-20
Status: Research / recommendation
Audience: Product + engineering decision on whether and how Euno should integrate with LinkedIn

## Verdict

**Do not build a LinkedIn data/API integration for importing or enriching other people's profiles.**
LinkedIn locks that behind partner approval, and it fights Euno's product shape.

**Do keep treating LinkedIn as a first-class capture source** (already done).
The real gap is UX: LinkedIn profile URLs cannot be derived from screenshots, so the triage flow should lean harder on paste-a-link when the platform is LinkedIn.

**Optional later:** "Sign in with LinkedIn" via Clerk is low effort and legal, but it only helps auth conversion - not the core recall loop.

---

## What Euno already does with LinkedIn

LinkedIn is already in the product surface, without any LinkedIn API:

| Surface | Behavior today |
| --- | --- |
| Screenshot capture | `openaiClient.ts` treats `linkedin` as a first-class platform enum; vision extraction pulls name / handle / headline / bio when visible. |
| Profile URL derivation | `deriveProfileUrl("linkedin", ...)` returns `null`. Comment in `src/lib.ts`: LinkedIn (and Facebook) use slugs that do not appear in profile screenshots. |
| Triage UI | When no URL can be derived, CaptureTriage shows an optional "Their profile link" field and `normalizeUrl` accepts bare `linkedin.com/in/...`. |
| Person record | Optional `link` stores whatever the user pastes (often a LinkedIn URL). |
| Auth | Clerk; Google OAuth is referenced in comments. LinkedIn OIDC is not enabled in-app yet, but Clerk supports it as a dashboard toggle. |

MVP design already called LinkedIn out as a typical value for `people.link`, and listed bulk import (Apple Contacts) as explicitly out of scope.
LinkedIn connection import is the same class of feature.

---

## Integration options evaluated

### 1. Import the user's LinkedIn connections

**What people usually mean:** "Connect LinkedIn -> seed my people list."

**API reality (2026):**

- Connections API exists (`GET /v2/connections?q=viewer`) but is **partner-gated**. Microsoft docs: restricted to LinkedIn-approved developers.
- Even if approved: only **1st-degree** connections of the consenting member; no 2nd-degree browse; fields are thin (person URN, optionally first/last name).
- Self-serve OAuth scopes for any developer app are essentially: `openid` / `profile` / `email` (Sign In with LinkedIn) and `w_member_social` (post on their behalf). **Not** connections, full work history, or arbitrary profile lookup.

**Product fit:** Poor.

- PRODUCT.md: private memory layer; anti-CRM / anti-network.
- Spec future list puts Contacts-style seeding as "not now."
- A friend list without *how you met* is exactly the empty social-media model Euno is meant to replace.

**Recommendation:** Skip.
Revisit only if LinkedIn grants a clear partner path *and* product deliberately wants a seed-the-catalog moment (same conversation as Apple Contacts).

### 2. Export your own connections via LinkedIn's data export (CSV)

**What people usually mean:** Same goal as option 1 (seed my people list from LinkedIn), reached through the export button every member already has instead of an API.

**How it works today:** LinkedIn Settings > Data privacy > "Get a copy of your data" lets any member request an export of their own account data.
Connections is one of the selectable categories, and LinkedIn emails a CSV (or a zip containing one) once it is ready, typically within minutes to about a day.
The connections CSV commonly includes First Name, Last Name, Company, Position, Connected On (date), and, when the connection has chosen to make it visible, Email Address.

**Feasibility:** Fully feasible and legal, right now, with zero LinkedIn involvement on Euno's side.
This is a member exporting their own data through LinkedIn's own privacy tooling, not an API integration and not scraping.
It needs no LinkedIn developer app, no partner approval, and carries no ToS risk, since the user (not Euno) is the one pulling the file; Euno would only need to accept a CSV upload.
The limits are real: 1st-degree connections only, no guarantee of an email address per row, and critically no "how you met" context.
The file is a contact list, not a memory.

**Product fit:** Weak, for the same reason as option 1.

- PRODUCT.md: private memory layer; anti-CRM / anti-network.
- MVP spec: bulk import is explicitly out of MVP scope.
- A flat contact list without *how you met* is exactly the empty social-media model Euno is meant to replace; CSV rows do not carry the story that makes a person memorable in Euno.

**Recommendation:** Not now.
If product ever deliberately reopens Contacts-style seeding (the same conversation as Apple Contacts import), this CSV export - not the Connections API - is the realistic route in: it is legal today, needs no partnership, and every user already has access to it.

### 3. Enrich a person from a pasted LinkedIn URL

**What people usually mean:** User pastes `linkedin.com/in/...` -> Euno fills name, headline, company.

**API reality:** Official LinkedIn APIs do **not** support looking up arbitrary members by public profile URL for general apps.
Partner products (Talent / Sales Navigator SNAP) are seat- and approval-based, aimed at recruiting/sales - wrong category for Euno.

**Scraping / third-party "LinkedIn data APIs":** Legally and ToS-hostile.
Proxycurl shut down under LinkedIn legal pressure; remaining scrapers are high risk and wrong for a calm, private consumer product.

**Recommendation:** Do not scrape.
Do not apply for Sales/Talent APIs for this.
Keep the model: user (or screenshot OCR) supplies the memory; the link is a door out, not a data source in.

### 4. Sign in with LinkedIn (OIDC via Clerk)

**What it is:** Auth only - name, photo, email of the *signed-in user*.

**Effort:** Dashboard config for Clerk LinkedIn OIDC; prod needs a LinkedIn developer app + "Sign In with LinkedIn using OpenID Connect" product.
Little or no Euno code if `<SignIn />` already shows enabled providers.

**Product fit:** Neutral.
Helps people who live in LinkedIn identity; does not help recall.
Does not unlock connections or other people's profiles.

**Recommendation:** Optional growth/auth experiment.
Not required for LinkedIn *product* value.
Prefer after Google (or whatever is already primary) is solid.

### 5. Post / share to LinkedIn (`w_member_social`)

Out of scope for Euno's one job (hand back a person so you can reach out yourself).
Skip.

### 6. Deepen LinkedIn-aware capture (no LinkedIn API)

**This is the high-leverage path.**

Gaps today:

1. **URL:** LinkedIn vanity slug rarely appears in screenshots -> `deriveProfileUrl` correctly returns null -> link is optional and easy to skip.
2. **Copy:** Placeholder is generic ("Their profile link") even when platform is known LinkedIn.
3. **Extraction:** Prompt is platform-generic; LinkedIn screenshots often show title + company + location that could land in `headline` / `bio` more reliably with platform-aware guidance.
4. **Manual failed cards:** Manual naming collects work/school but still no LinkedIn link field on that path (only ready cards get the link input).

**Recommended product moves (implementation-sized, no partner approval):**

| Priority | Change | Why |
| --- | --- | --- |
| P0 | When `platform === "linkedin"`, use LinkedIn-specific link placeholder / helper ("Paste their LinkedIn URL - it is not on the screenshot") | Closes the known derive-URL hole without API |
| P1 | Same paste affordance on failed/manual LinkedIn captures (and/or person detail) | Link often arrives after naming |
| P2 | Slightly tighten extraction prompt for LinkedIn layouts (headline = title + company) | Better search/embed text from existing vision path |
| P3 | Optional: detect `linkedin.com` in pasted text and normalize vanity URLs more carefully | Already mostly covered by `normalizeUrl` |

None of this needs LinkedIn developer partnership.

---

## Fit against Euno principles

| Principle | LinkedIn connections/API import | Capture + paste link |
| --- | --- | --- |
| Hand back the person, not a dashboard | Fails - dumps a network graph | Passes |
| No CRM / scoring | Borderline - looks like lead import | Passes |
| Private, user-authored memory | Contested - LinkedIn's data + retention rules | Passes |
| MVP "link + context" loop | Overbuilds | Extends existing loop |

---

## Decision matrix

| Option | Feasible without partnership? | Product fit | Recommend |
| --- | --- | --- | --- |
| Connections import (API) | No | Weak | No |
| Connections export (CSV, user-initiated) | Yes | Weak | No |
| URL -> profile enrich via API | No (self-serve) | Weak / CRM-ish | No |
| Scraping / third-party LinkedIn data | Technically yes, ToS/legal no | Weak | No |
| Sign in with LinkedIn (Clerk) | Yes | Auth only | Optional later |
| LinkedIn-aware capture UX | Yes | Strong | **Yes - do this** |

---

## Suggested next step

Ship a small capture/triage improvement for LinkedIn link paste (P0/P1 above).
Treat any "Connect LinkedIn" marketing language as **auth**, not **import**, unless product later reopens Contacts-style seeding as a deliberate milestone.

## Sources

- [LinkedIn Connections API (Microsoft Learn)](https://learn.microsoft.com/en-us/linkedin/shared/integrations/people/connections-api) - partner-restricted; 1st-degree only
- [Clerk: LinkedIn OIDC social connection](https://clerk.com/docs/guides/configure/auth-strategies/social-connections/linkedin-oidc)
- LinkedIn Help Center: "Downloading your account data" (Settings > Data Privacy > Get a copy of your data) - user-initiated export, no developer/partner approval required
- Industry summary of 2026 self-serve scopes (`profile` / `email` / `w_member_social`) vs partner-gated Marketing / Talent / Sales APIs
- In-repo: `PRODUCT.md`, `docs/superpowers/specs/2026-07-15-euno-mvp-design.md`, `src/lib.ts`, `convex/openaiClient.ts`, `src/CaptureTriage.tsx`
