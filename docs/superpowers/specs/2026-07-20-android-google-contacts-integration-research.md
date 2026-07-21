# Android/Google Contacts Integration Research

Date: 2026-07-20
Status: Research / recommendation
Audience: Product + engineering decision on whether Euno should integrate with Android/Google Contacts to import or seed a user's own contacts

## Verdict

**Do not build a Google Contacts bulk-import feature for the MVP.**
The reason is product fit, not technical feasibility.

**This case is technically different from LinkedIn, and the difference matters for any future decision.**
Google's People API exposes a self-serve OAuth scope (`contacts.readonly`) that lets any developer, with no partner approval and no business relationship with Google, ask a signed-in user to grant read access to their own Google Contacts.
That is a real, buildable path today, unlike LinkedIn's Connections API, which is partner-gated and closed to ordinary developers.

**The blocker is still Euno's own product scope.**
PRODUCT.md and the MVP design doc explicitly rule out bulk import for the MVP, and a flat contacts dump has the same "friend list without a story" problem the whole product is designed against, regardless of which vendor's API supplies the list.

**Android's OS-level Contacts provider (`ContactsContract`) is not applicable.**
Euno is a web app running in a browser, not a native Android app, so that API surface is simply out of reach and not worth discussing further.

**If product ever reopens "seed the catalog" as a deliberate milestone** (the same conversation as Apple Contacts, already named in the MVP doc's Future section), Google's OAuth path is the strongest candidate among every bulk-import mechanism evaluated across the sibling research docs, because it is the only one that is both legal and self-serve without waiting on anyone's approval.
It still requires real lead time (Google's app-verification review) and still needs a deliberate product decision about "how you met" context, which no import mechanism supplies on its own.

---

## What Euno already does with Android/Google

There is no Google Contacts code in the repo today.
The only existing Google surface is auth:

| Surface | Behavior today |
| --- | --- |
| Sign-in | Clerk drives auth; `src/App.tsx` mounts `<ClerkSignIn />`. A comment in `src/lib.ts` (`isClerkFlowHash`) confirms Google is already a live Clerk OAuth provider: "Clerk drives OAuth and verification steps through hash sub-routes it appends to our page, e.g. `#/sso-callback` after Google returns." |
| Scope requested | Whatever Clerk's default Google connection requests for sign-in (profile/email), not Contacts. No custom scope has been configured. |
| Contacts API | None. No `people.googleapis.com` calls, no Contact Picker usage, no vCard/CSV import path anywhere in `src/` or `convex/`. |
| Android native | Not applicable; Euno ships no native Android app, so `ContactsContract` is unreachable regardless of product decisions. |

The MVP design doc lists "Apple Contacts or any bulk import" as explicitly out of scope for the MVP, and repeats it in the Future section as "Apple Contacts import to seed the back catalog" (not now, but the model allows it).
Google Contacts import is the same class of feature and was not separately named, but falls under the same "any bulk import" line.

---

## Integration options evaluated

### 1. Google People API, self-serve OAuth (`contacts.readonly`)

**What people usually mean:** "Sign in with Google, and let Euno read my Google Contacts to seed my people list."

**API reality (2026):**

- The API is the People API (`people.googleapis.com`), the successor to the old Contacts API v3, which Google has fully retired.
- The read scope is `https://www.googleapis.com/auth/contacts.readonly`.
- The call to list a signed-in user's contacts is `GET /v1/people/me/connections?personFields=names,emailAddresses` (add more `personFields` such as `phoneNumbers`, `organizations`, `photos` as needed).
- Unlike LinkedIn's Connections API, this scope is **not partner-gated**. Any developer with a Google Cloud project can request it from any consenting Google user; no application to a partner program, no approval committee.
- It is, however, classified by Google as a **sensitive scope** (not the more severe "restricted" tier reserved for things like full Gmail or Drive content). Sensitive-scope apps must complete Google's standard OAuth app verification: brand verification, a data-access review with a justification and an unlisted YouTube demo video, and proof of domain ownership. Google's own guidance puts the review at up to about 10 days once a submission is complete, though real-world reports (forum and blog accounts) describe it commonly running several weeks and occasionally months when submissions bounce back for clarification.
- Because `contacts.readonly` is sensitive rather than restricted, it does **not** require the annual CASA third-party security assessment that restricted scopes (like full Gmail/Drive access) require. That is a meaningfully lighter compliance bar than the "restricted scope" framing sometimes assumed for any contacts-adjacent API.
- Before verification, the app runs in "Testing" status: capped at 100 test users, and each test user's grant expires after 7 days, which is fine for internal dogfooding but not for a real launch.
- Clerk (Euno's auth provider) does not request `contacts.readonly` by default and has no first-class UI for "add this extra Google scope" on its shared/managed OAuth credentials. To request additional scopes, a Clerk project must switch that connection to "custom credentials" (its own Google Cloud OAuth client ID/secret) and configure the scope there; Clerk's docs describe this as the supported path but note optional/per-user scopes need extra handling since they cannot simply be forced onto every sign-in.
- Because a one-time seed import needs only a single read, not continuous sync, Euno would not need an offline/refresh token strategy or ongoing storage of Google credentials, which shrinks the security surface relative to a "keep syncing forever" design.

**Feasibility:** High, from a pure API-and-scope standpoint.
This is the one bulk-import mechanism across both this doc and the LinkedIn doc that a small team could actually ship without anyone else's permission.
The cost is calendar time (verification lead time, a real privacy policy, a demo video) and an engineering decision to run a second Google OAuth client outside Clerk's shared credentials, not a legal or partnership blocker.

**Product fit:** Weak, for the same reason as every bulk-import option evaluated in the LinkedIn doc.

- PRODUCT.md: private memory layer, explicitly anti-CRM and anti-social-graph.
- MVP doc: "Apple Contacts or any bulk import" is out of MVP scope; the general pattern ("import your contacts") is also the default building block of every CRM and sales tool, which is exactly the category Euno's anti-references reject.
- A row of `{name, email, phone}` from Google Contacts carries no "how you met" story, which is the one thing that makes a person findable and memorable in Euno's model. Seeding hundreds of contentless rows would bury the handful of people a user actually wants to keep track of.

**Recommendation:** Do not build now.
If product deliberately reopens Contacts-style seeding, this is the realistic technical route: file for Google's sensitive-scope verification early (it is the long pole), and design the import as an opt-in, explicitly-labeled "seed" step that still asks for at least one piece of context per person, rather than a silent bulk dump.

### 2. Native Android `ContactsContract` content provider

**What people usually mean:** "Euno should read the Contacts app directly on an Android phone."

**Reality:** `ContactsContract` is an Android OS content-provider API, reachable only from a native Android app (Kotlin/Java) holding the `READ_CONTACTS` runtime permission.
It has no web-facing equivalent and cannot be called from a browser or a PWA.

**Feasibility:** Not applicable to Euno's stack.
Euno is a Vite/React web app; building a native Android client just to reach this API would be a far larger undertaking than the feature it would unlock, and nothing in PRODUCT.md or the MVP doc suggests a native app is planned.

**Recommendation:** Skip.
Revisit only if Euno ever ships a native Android app for reasons unrelated to contacts import.

### 3. W3C Contact Picker API (`navigator.contacts.select(...)`)

**What people usually mean:** A lighter-weight "let me tap one contact from my phone's address book to attach to this person," rather than a bulk import.

**API reality (2026):**

- This is a browser API, not a Google API; it works against whatever contacts source the OS/browser is backed by (on Android, that is typically the device's Google-synced contacts).
- Support is narrow: Chrome/Chromium on Android (from Chrome 80, Android M or later), plus similar Chromium-based mobile browsers such as Samsung Internet. It is not available on desktop Chrome, not on any Firefox, and not on Safari (desktop or iOS).
- MDN and the W3C spec both mark it as an experimental, non-Baseline feature; MDN's own guidance is to check current compatibility before relying on it in production.
- Selectable fields are limited to `name`, `email`, `tel`, and (from Chrome 84) `address` and `icon`; labels and other semantic metadata on those fields are dropped.
- It requires a secure context (HTTPS) and a direct user gesture, and each call surfaces the browser's own native picker UI rather than anything Euno can restyle.

**Feasibility:** Feasible only as a narrow, Android-Chrome-only enhancement, not as Euno's contacts story.
Given Euno's userbase likely spans iOS Safari and desktop as well as Android Chrome, a feature that only works on one browser/OS combination would be an inconsistent, confusing affordance rather than a real capability.

**Product fit:** Neutral-to-weak on its own merits (feature-detect-and-degrade adds UI complexity for a feature only a fraction of visits could use); the "attach one contact's name/phone/email to a person" idea is closer to Euno's single-person, context-first model than a bulk import, but it still doesn't solve the "how you met" problem, and it's low value while so much of the audience can't use it.

**Recommendation:** Skip for now.
Not worth the maintenance cost of a browser-specific code path for a niche convenience.
Reconsider only if Contact Picker gains broader (especially iOS Safari) support, or if product wants a very small "attach a phone number in one tap" affordance specifically for Android-Chrome users and is comfortable with everyone else seeing no button.

### 4. vCard/CSV export from Google Contacts (user-initiated, no API)

**What people usually mean:** Same end goal as option 1 (seed my people list from Google Contacts), reached through the export button every Google user already has, instead of an API and OAuth consent screen.

**How it works today:** `contacts.google.com` has an Export option (left-hand menu) that produces a Google CSV, an Outlook CSV, or a vCard (`.vcf`) file of the user's own contacts, generated instantly with no waiting period.
Google Takeout offers the same data as part of a full account export, also as vCard, for a broader "back up everything" use case.
The exported file commonly includes name, email addresses, phone numbers, and any organization/title fields the user filled in; it carries no "how you met" story, same as the LinkedIn connections CSV.

**Feasibility:** Fully feasible and legal right now, with zero Google involvement on Euno's side.
This is a user exporting their own data through Google's own tooling, not an API integration, so it needs no OAuth client, no Google Cloud project, no sensitive-scope verification, and carries no ToS risk for Euno; Euno would only need to accept a CSV/vCard file upload and parse it.
The tradeoffs mirror the LinkedIn CSV option: it's a flat contact list, not a memory, and it puts the export/upload burden entirely on the user (find the button, download the file, find Euno's upload control), which is more friction than a "Sign in with Google" button, even though it needs no verification lead time.

**Product fit:** Weak, for the same reasons as option 1 and the LinkedIn CSV option.

**Recommendation:** Not now.
If product ever reopens Contacts-style seeding, keep this in the back pocket as the zero-infrastructure fallback (useful for a quick prototype, or for users on a browser/OS combination where OAuth or Contact Picker don't apply), but the OAuth path in option 1 is the better default once verification is done, since it removes the "download a file, then upload it" step entirely.

---

## Fit against Euno principles

| Principle | Google Contacts OAuth import (bulk) | Contact Picker (single contact, Android-only) | CSV/vCard export+upload | Capture + paste link (status quo) |
| --- | --- | --- | --- | --- |
| Hand back the person, not a dashboard | Fails - seeds a flat list, not a person with a story | Neutral - one contact, still no story | Fails - same flat-list problem | Passes |
| No CRM / scoring | Fails - "import your contacts" is the default CRM onboarding pattern | Passes | Fails - same reason as bulk OAuth | Passes |
| Private, user-authored memory | Contested - data comes from Google, not authored by the user in Euno | Contested, but smaller blast radius (one contact at a time) | Contested - same as OAuth import | Passes |
| MVP "link + context" loop | Overbuilds; needs a whole second data-entry model to backfill context | Mild overbuild - one tap, but still no context capture | Overbuilds, plus manual file handling | Extends existing loop |

---

## Decision matrix

| Option | Feasible without partnership? | Verification/compliance lead time | Product fit | Recommend |
| --- | --- | --- | --- | --- |
| Google People API, self-serve OAuth (`contacts.readonly`) | Yes | Sensitive-scope verification (roughly days to a few weeks; no annual CASA assessment) | Weak | No, for now |
| Native Android `ContactsContract` | N/A (not a web API) | N/A | N/A | Not applicable to a web app |
| W3C Contact Picker API | Yes, but Android Chrome only | None (browser feature, no consent screen) | Weak/neutral, and narrow reach | No |
| vCard/CSV export (user-initiated) | Yes | None | Weak | No |
| Sign in with Google via Clerk (auth only, already live) | Yes (already shipped) | None beyond what's already done | Neutral - auth, not import | Already in place; no change needed |

---

## Suggested next step

No engineering work now.
If and when product deliberately reopens "seed the catalog" (Apple Contacts / Google Contacts / LinkedIn connections, all the same conversation), treat Google's OAuth path as the front-runner on technical grounds, start Google's sensitive-scope verification early since it is the long pole, and design the import step to require at least a one-line "how you met" prompt per person rather than a silent bulk insert, so the feature stays consistent with Euno's memory-first model instead of becoming a contacts dump.

## Sources

- [Introduction, People API (Google for Developers)](https://developers.google.com/people)
- [Read and Manage Contacts, People API (Google for Developers)](https://developers.google.com/people/v1/contacts)
- [Contacts API Migration Guide, People API (Google for Developers)](https://developers.google.com/people/contacts-api-migration)
- [OAuth 2.0 Scopes for Google APIs (Google for Developers)](https://developers.google.com/identity/protocols/oauth2/scopes)
- [Sensitive scope verification, App verification to use Google Authorization APIs (Google for Developers)](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification)
- [Restricted scope verification, App verification to use Google Authorization APIs (Google for Developers)](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- [OAuth API Verification FAQ (Google Cloud Platform Console Help, support.google.com/cloud/answer/9110914)](https://support.google.com/cloud/answer/9110914)
- [Manage App Audience / testing status and 100-user cap (Google Cloud Platform Console Help)](https://support.google.com/cloud/answer/15549945)
- [Unverified apps (Google Cloud Platform Console Help)](https://support.google.com/cloud/answer/7454865)
- [Google CASA - Cloud Application Security Assessment (DeepStrike)](https://deepstrike.io/blog/google-casa-security-assessment-2025)
- [Five annoying issues with Google's OAuth Scope Verification (GMass)](https://www.gmass.co/blog/five-annoying-issues-google-oauth-scope-verification/)
- [Contact Picker API, MDN Web Docs](https://developer.mozilla.org/en-US/docs/Web/API/Contact_Picker_API)
- [A contact picker for the web, Chrome for Developers](https://developer.chrome.com/docs/capabilities/web-apis/contact-picker)
- [Contact Picker API specification, W3C](https://www.w3.org/TR/contact-picker/)
- [w3c/contact-picker README, GitHub](https://github.com/w3c/contact-picker/blob/main/README.md)
- [Export, back up, or restore contacts (Google Contacts Help)](https://support.google.com/contacts/answer/7199294)
- [Add Google as a social connection, Clerk Docs](https://clerk.com/docs/guides/configure/auth-strategies/social-connections/google)
- [How to implement per-user OAuth scopes with Clerk (Clerk blog)](https://clerk.com/blog/implement-per-user-oauth-with-clerk)
- In-repo: `PRODUCT.md`, `docs/superpowers/specs/2026-07-15-euno-mvp-design.md`, `src/lib.ts`, `src/App.tsx`
