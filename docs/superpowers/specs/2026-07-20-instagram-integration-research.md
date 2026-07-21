# Instagram Integration Research

Date: 2026-07-20
Status: Research / recommendation
Audience: Product + engineering decision on whether and how Euno should integrate with Instagram

## Verdict

**Do not build an Instagram data/API integration for importing followers/following or enriching other people's profiles.**
Meta's official API surface does not even offer that access to apply for; the only paths in are scraping (ToS-hostile, aggressively enforced) or the user's own personal data export (legal, but the wrong shape of data for Euno).

**Do keep treating Instagram as a first-class capture source** (already done), and note that its capture story is already more complete than LinkedIn's: Instagram profile URLs derive directly from the handle, so there is no equivalent "paste the link" gap to close.

**There is no viable "Sign in with Instagram" analog** to LinkedIn's OIDC-via-Clerk option.
Instagram Login is scoped to professional-account management (creators/businesses managing their own presence), not general consumer identity, so it is not a real substitute for LinkedIn's auth path.

---

## What Euno already does with Instagram

Instagram is already in the product surface, without any Instagram API:

| Surface | Behavior today |
| --- | --- |
| Screenshot capture | `openaiClient.ts` treats `instagram` as a first-class platform enum; vision extraction pulls name / handle / headline / bio when visible. |
| Profile URL derivation | `deriveProfileUrl("instagram", handle)` returns `https://instagram.com/<handle>` (`src/lib.ts`). Instagram handles are visible on-screen, so this works whenever a handle was extracted. Unlike LinkedIn (vanity slug not on-screen, always returns `null`), Instagram is a "handle URL" platform alongside X, GitHub, TikTok, Threads, and Bluesky. |
| Triage UI | `CaptureTriage.tsx` renders the derived Instagram URL as a read-only `sky-link-pill`; there is no manual link-paste field for Instagram captures the way there is for LinkedIn/Facebook, because none is needed. |
| Person record | Optional `link` stores the derived (or pasted) URL. |
| Auth | Clerk; Google OAuth is referenced in comments. No Instagram sign-in of any kind is wired up, and (see Option 4 below) there is no clean equivalent to offer. |

MVP design already called out bulk import (Apple Contacts) as explicitly out of scope, and PRODUCT.md frames Euno as an anti-CRM, anti-network memory layer.
A followers/following import from Instagram is the same class of feature LinkedIn connection import would have been, arguably a worse fit (see Fit table).

---

## Integration options evaluated

### 1. Import the user's Instagram followers/following

**What people usually mean:** "Connect Instagram -> seed my people list from who follows me / who I follow."

**API reality (2026):**

- The Instagram Basic Display API, which was the closest thing to a personal-account read API, was fully deprecated by Meta on December 4, 2024. Meta's replacement is "Instagram API with Instagram Login."
- Instagram API with Instagram Login, per Meta's own developer documentation, requires an Instagram Business or Creator account. Personal accounts have no supported API access at all after the Basic Display API shutdown; a user would have to convert their account type just to be eligible.
- There is no followers-list or following-list endpoint in the current Instagram Graph API / Instagram API with Instagram Login. The closest read is the Business Discovery endpoint, which returns aggregate metadata (follower count, media count) about a *public Business or Creator account*, not the individual accounts behind that count, and not for the caller's own personal relationships either.
- Where LinkedIn at least has a partner-gated Connections API that approved partners can apply for, Instagram has no equivalent endpoint to apply for at any tier. This is a harder "no" than LinkedIn's.

**Product fit:** Poor, and worse than LinkedIn connections (see Fit table below): a follower/following list is asymmetric audience/broadcast data, not a record of people the user actually met or has a relationship with.

**Recommendation:** Skip.
There is no partner tier to revisit this against; it would require Meta to ship a new endpoint that does not exist today.

### 2. Export your own followers/following via Instagram's "Download Your Information"

**What people usually mean:** Same goal as option 1, reached through the export tool every Instagram account already has instead of an API.

**How it works today:** Instagram's Help Center describes "Download Your Information" / "Review and export a copy of your Instagram information" as a self-serve export any account holder can request from Accounts Center, available in JSON or HTML format.
Community documentation of the actual exported files (corroborated across multiple independent write-ups, since Meta's own Help Center pages do not publish the internal file schema) describes the connections data landing under a `connections/followers_and_following/` folder: `following.json` holding a `relationships_following` list and one or more `followers_1.json` (`followers_2.json`, etc. for larger accounts) holding `relationships_followers`, each entry a `string_list_data` record with `href`, `value` (the handle), and a `timestamp`.

**Feasibility:** Fully feasible and legal, right now, with zero Meta involvement on Euno's side.
This is a member exporting their own data through Meta's own privacy tooling, not an API integration and not scraping.
It needs no developer app, no app review, no business verification, and carries no ToS risk since the user, not Euno, pulls the file; Euno would only need to accept a JSON/zip upload.
The limits are real: a handle and a timestamp per row, no name, no bio, and critically no "how you met" context.
It is a list of usernames, not a memory.

**Product fit:** Weak, and weaker than LinkedIn's CSV-export option for the same reason as option 1: this is audience data (who follows the account, who the account follows), not a curated list of relationships, let alone ones with any shared context.

**Recommendation:** Not now.
If product ever deliberately reopens Contacts-style seeding, this export is the technically realistic route in (legal today, no partnership needed), but the data itself argues against it more strongly than LinkedIn's connections CSV did.

### 3. Enrich a person from a pasted Instagram handle/URL

**What people usually mean:** User pastes `instagram.com/someuser` or a handle -> Euno fills name, bio, follower count.

**API reality:** The Business Discovery endpoint can look up metadata for another *public Business or Creator* account by username, but this is narrow (aggregate metrics, professional accounts only) and still requires the caller's own account to be a Business/Creator account with Instagram Login connected.
It is not a general profile-lookup-by-URL API, and it does not work for the personal accounts most of the people someone would want to remember actually have.

**Scraping / third-party "Instagram data APIs":** Legally and ToS-hostile, and Meta has a documented history of aggressive enforcement:

- *Meta Platforms, Inc. v. Bright Data* (N.D. Cal., ruling Jan. 23, 2024): the court sided with Bright Data, holding that Meta's terms of service restricting scraping apply only to logged-in use, not to scraping data that is publicly visible while logged out.
  This narrows what Meta can win on in court, but it does not make scraping safe: most useful profile data (followers, following, private-account content) is only fully visible logged in, which is exactly the behavior Meta can and does enforce against.
- *Meta v. Voyager Labs*: Meta sued Voyager Labs (a surveillance-analytics vendor) for using roughly 38,000 fake accounts to scrape data, including friends/connections lists, from more than 600,000 Facebook and Instagram users; the case settled with Voyager Labs required to delete the collected data and stop scraping Meta platforms.
- Meta has publicly framed "scraping-for-hire" as an ongoing enforcement priority (account takedowns, cease-and-desist, litigation), not a one-off action.

**Recommendation:** Do not scrape.
Do not build against unofficial "Instagram data API" resellers.
Keep the model: the user (or screenshot OCR) supplies the memory; the link is a door out, not a data source in.

### 4. Sign in with Instagram

**What it is:** Unlike LinkedIn's "Sign In with LinkedIn using OpenID Connect," which is a clean consumer-identity OIDC product, Instagram Login (the auth flow underlying "Instagram API with Instagram Login") is scoped to professional accounts connecting a business/creator identity so an app can manage their presence (messaging, comments, publishing).
It is not marketed or documented as a general-purpose "log in with your Instagram account" identity provider for arbitrary consumer apps, and it requires the account to be Business/Creator, which most people signing up for a personal memory app will not have.

**Product fit:** N/A -- there is no equivalent feature to evaluate.
Clerk does not list an Instagram social-connection provider alongside its LinkedIn OIDC option, consistent with this not being a general auth product.

**Recommendation:** Skip.
Do not promise "Sign in with Instagram" as a LinkedIn-equivalent; the underlying product does not exist in that shape.

### 5. Deepen Instagram-aware capture (no Instagram API)

Unlike LinkedIn, there is no meaningful capture gap to close here.
`deriveProfileUrl` already produces a working Instagram URL whenever a handle is visible in the screenshot (the common case, since Instagram surfaces the handle prominently in its UI), and `CaptureTriage` already renders it automatically with no manual paste step.
The one plausible, small improvement is a slightly more Instagram-aware extraction prompt (e.g., distinguishing a bio link from the bio text itself), but this is a minor polish item, not a gap on the scale of LinkedIn's missing-URL problem.

**Recommendation:** No dedicated workstream needed.
If extraction quality issues surface for Instagram screenshots specifically, address them as part of general prompt tuning, not as an "Instagram integration."

---

## Fit against Euno principles

| Principle | Instagram followers/following import | Capture + derived link (current) |
| --- | --- | --- |
| Hand back the person, not a dashboard | Fails - dumps an audience list, not a person | Passes |
| No CRM / scoring | Fails - a follower count is the definition of a vanity metric | Passes |
| Private, user-authored memory | Contested - Meta's data, no user-authored context at all | Passes |
| "People I met," not "people who follow me" | Fails hardest of any option considered here - following/followers is asymmetric broadcast data, not a relationship signal; a follower is not someone the user necessarily ever met | Passes - capture starts from an actual screenshot of an actual interaction |
| MVP "link + context" loop | Overbuilds, and still needs a context field bolted on after the fact | Extends existing loop, no change needed |

The "even worse fit than LinkedIn" concern raised for this research holds up: LinkedIn connections are at least mutual, professional, opt-in ties.
Instagram followers/following is one-directional audience data that says nothing about whether the user has ever interacted with, let alone met, the other party.

---

## Decision matrix

| Option | Feasible without partnership? | Product fit | Recommend |
| --- | --- | --- | --- |
| Followers/following import (API) | No - endpoint does not exist at any access tier | Poor (worse than LinkedIn) | No |
| Followers/following export (JSON, user-initiated) | Yes | Poor (worse than LinkedIn) | No |
| Handle/URL -> profile enrich via API | No (Business Discovery is narrow, professional-account-only, and still not general lookup) | Weak | No |
| Scraping / third-party Instagram data | Technically yes, ToS/legal no, aggressively enforced | Weak | No |
| Sign in with Instagram | Not a comparable product to LinkedIn OIDC | N/A | No |
| Instagram-aware capture UX | Yes (already shipped) | Strong | Already done - minor polish only |

---

## Suggested next step

No new workstream.
Instagram's capture path is already in good shape (derived URL, no manual paste needed), and every import/enrichment path is either technically nonexistent, ToS-hostile, or a worse product fit than the LinkedIn options Euno already declined.
If Instagram-screenshot extraction quality issues come up in practice, fold a prompt tweak into general vision-extraction polish rather than opening an "Instagram integration" effort.

## Sources

- [Instagram Platform overview (Meta for Developers)](https://developers.facebook.com/docs/instagram-platform/overview) - Advanced Access requires App Review; Business Verification required for apps serving accounts the developer does not own
- [Instagram API with Instagram Login (Meta for Developers)](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login) - requires an Instagram Business or Creator account; no followers/following endpoint documented
- [Instagram Platform (Meta for Developers, landing page)](https://developers.facebook.com/docs/instagram-platform) - confirms Business/Creator-only support, no personal-account API access
- [Business Discovery API (Meta for Developers)](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/business-discovery) - returns aggregate metadata/counts for public professional accounts only, not individual follower lists
- [Meta Platforms, Inc. v. Bright Data - court ruling summary (MediaPost)](https://www.mediapost.com/publications/article/392920/bright-data-didnt-violate-metas-terms-by-scrapin.html) - N.D. Cal. ruling that Meta's ToS restrict only logged-in scraping, not logged-out public scraping
- [Meta Fails to Beat Data Firm in Facebook, Instagram Scraping Row (Bloomberg Law)](https://news.bloomberglaw.com/ip-law/meta-fails-to-beat-data-firm-in-facebook-instagram-scraping-row) - additional coverage of the Bright Data ruling
- [Meta sues surveillance company for allegedly scraping more than 600,000 accounts (Engadget)](https://www.engadget.com/meta-lawsuit-data-scraping-facebook-instagram-voyager-labs-180139048.html) - Voyager Labs lawsuit, fake-account scraping of friends/connections lists
- [Analytics Company Voyager Labs Settles Scraping Battle With Meta (MediaPost)](https://www.mediapost.com/publications/article/401661/analytics-company-voyager-labs-settles-scraping-ba.html) - settlement terms (data deletion, scraping ban)
- [Leading the Fight Against Scraping-for-Hire (Meta, About Meta)](https://about.fb.com/news/2023/01/leading-the-fight-against-scraping-for-hire/) - Meta's own framing of scraping enforcement as an ongoing priority
- [Review and export a copy of your Instagram information (Instagram Help Center)](https://help.instagram.com/181231772500920) - official pointer to the "Download Your Information" export tool (JSON/HTML)
- [Information available to download from your Instagram profile (Instagram Help Center)](https://help.instagram.com/6947552812036899/) - official list of exportable data categories, including connections
- In-repo: `PRODUCT.md`, `docs/superpowers/specs/2026-07-15-euno-mvp-design.md`, `docs/superpowers/specs/2026-07-20-linkedin-integration-research.md`, `src/lib.ts`, `convex/openaiClient.ts`, `src/CaptureTriage.tsx`

Note: the exact JSON schema of the Instagram data export (`connections/followers_and_following/following.json`, `followers_1.json`, `relationships_following`/`relationships_followers`, `string_list_data` with `href`/`value`/`timestamp`) is corroborated across multiple independent third-party write-ups of real exports, since Meta's own Help Center pages describe the feature but do not publish the internal file schema.
