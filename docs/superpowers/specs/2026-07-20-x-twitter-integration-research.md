# X (Twitter) Integration Research

Date: 2026-07-20
Status: Research / recommendation
Audience: Product + engineering decision on whether and how Euno should integrate with X (formerly Twitter)

## Verdict

**Do not build an X API integration for importing followers/following or for enriching other people's profiles.**
X's API moved to metered pay-per-use pricing in February 2026, which removed the old free tier entirely, and the "cheap" owned-reads rate that would make a followers/following sync affordable is itself unsettled - X's own developer community is still arguing about whether it applies to third-party apps like Euno.

**Do keep treating X as a first-class capture source** (already done, and further along than LinkedIn).
Unlike LinkedIn, X profile URLs derive automatically from the handle alone, so there is no known capture gap left to close.

**Do not lean on X's personal data export as a substitute for the API.**
Unlike LinkedIn's connections CSV, X's archive export gives only numeric account IDs for followers/following, not usernames or names, so it cannot seed a person record by itself.

**Optional later:** "Sign in with X" via Clerk is low effort (Clerk fully supports X/Twitter OAuth v2, with zero extra config on development instances) and legal, but it only helps auth conversion, not the core recall loop.

---

## What Euno already does with X

X is already in the product surface, without any X API, and its capture story is more complete than LinkedIn's:

| Surface | Behavior today |
| --- | --- |
| Screenshot capture | `openaiClient.ts` lists `x` as a first-class platform enum alongside `linkedin`, `instagram`, `tiktok`, `github`, `facebook`, `threads`, `bluesky`, `other`; vision extraction pulls name / handle / headline / bio when visible. |
| Profile URL derivation | `deriveProfileUrl("x", handle)` in `src/lib.ts` returns `https://x.com/<handle>` directly from the extracted handle. X is in the `HANDLE_URLS` map (with Instagram, GitHub, TikTok, Threads, Bluesky) precisely because the handle is visible on-screen and the URL needs no vanity slug the way LinkedIn and Facebook do. |
| Triage UI | `CaptureTriage.tsx` renders the derived `https://x.com/<handle>` as a read-only link pill for X captures; the optional "Their profile link" paste field only appears for platforms where `deriveProfileUrl` returns `null` (LinkedIn, Facebook), so X captures never hit that gap. |
| Platform label | `PLATFORM_LABELS` already maps `x` to the display string `"X"` (not the raw enum value), same treatment as LinkedIn, Instagram, etc. |
| Person record | Optional `link` stores the derived `x.com` URL, or whatever the user pastes for platforms that cannot be derived. |
| Auth | Clerk; Google OAuth is referenced in comments. X/Twitter OAuth is not enabled in-app yet, but Clerk supports it as a dashboard toggle, including a zero-config path on development instances. |

MVP design already called out an optional link on a person record with no bulk import in scope, and listed bulk import (Apple Contacts) as explicitly out of scope for the MVP.
An X followers/following import is the same class of feature as that out-of-scope Apple Contacts import.

---

## Integration options evaluated

### 1. Import the user's X followers/following via the API

**What people usually mean:** "Connect X -> seed my people list from who I follow or who follows me."

**API reality (2026):** X replaced its subscription tiers with pay-per-use pricing on February 6, 2026.
There is no free tier for new developers.
Legacy Basic ($200/month) and Pro ($5,000/month) subscriptions are closed to new signups and are being migrated to pay-per-use; Enterprise starts around $42,000/month for volume above the pay-per-use read cap.
Under pay-per-use, `GET /2/users/{id}/followers` and `GET /2/users/{id}/following` are billed as "Owned Reads" at $0.001 per resource (1,000 records for $1) when the request reads the authenticated user's own account through a user-context OAuth token.
Non-owned reads (looking up someone else's list) are billed at $0.005 per resource and, per multi-year developer-community reports, effectively require Enterprise access for followers/following of an arbitrary account.
Even the cheap path has real friction: it needs a registered X developer app, pre-purchased credits (no free trial of the endpoint itself), and a working OAuth 2.0 user-context sign-in flow, none of which exist in Euno today.
More importantly, whether the discounted "Owned Reads" rate even applies to a multi-tenant app like Euro reading many different end users' own follow graphs (versus only the app owner's single account) is disputed in X's own developer forum as of this pricing change; one active thread is titled "Owned Reads and Lists," another documents a billing bug where the discount silently did not apply to the bookmarks endpoint.
A pricing model that shipped in February 2026, had a billing correction announced for endpoints effective April 20, 2026, and is still being clarified by X's own developers is not a stable foundation to build a paid integration on.

**Product fit:** Poor, and arguably worse than LinkedIn's connections import.

- PRODUCT.md: private memory layer; anti-CRM / anti-network.
- Following/follower lists on X are a broadcast and interest graph (accounts you read, not necessarily people you have met), a weaker signal of "a person in your life" than even a LinkedIn connection.
- Spec's future list treats Contacts-style seeding as "not now," and this is the same category of feature.

**Recommendation:** Skip.
Revisit only if X's pricing and access model stabilizes and product deliberately wants a seed-the-catalog moment (same conversation as Apple Contacts) - and even then, only for interest-graph-flavored seeding, which does not fit Euno's "how you met" framing.

### 2. Export your own followers/following via X's data archive

**What people usually mean:** Same goal as option 1, reached through "Download an archive of your data" instead of the paid API.

**How it works today:** In X, the path is More > Settings and privacy > Your account > Download an archive of your data, confirm your password, then request the archive; X emails and shows an in-app notification when it is ready, and the download includes machine-readable JSON/JS files alongside an HTML viewer.
`follower.js` and `following.js` are part of that archive.

**Feasibility:** Legal and free, right now, with zero X API involvement - the same shape as LinkedIn's CSV export.
But the data is much thinner than LinkedIn's.
A first-hand technical breakdown of the archive format states plainly that the follower/following files contain only the numeric account ID of each account, not the username, handle, or display name; resolving an ID to a name requires another lookup, which is again gated behind the same paid, metered X API from option 1.
Where LinkedIn's connections CSV at least ships First Name, Last Name, Company, Position, and Connected On, X's export cannot name a single person without extra API calls.

**Product fit:** Weak, and weaker than the equivalent LinkedIn option.

- PRODUCT.md: private memory layer; anti-CRM / anti-network.
- MVP spec: bulk import is explicitly out of MVP scope.
- Even setting product fit aside, a list of anonymous numeric IDs cannot seed a person record with a name, so this option does not clear the bar of "a usable import" on its own merits.

**Recommendation:** Skip.
This is not a viable substitute for the API path the way LinkedIn's CSV export is; it would need a paid ID-to-username resolution step layered on top, at which point it is simply option 1 with extra steps.

### 3. Enrich a person from a pasted X handle or URL

**What people usually mean:** User pastes `x.com/handle` -> Euno fills name, bio, follower count.

**API reality:** Unlike LinkedIn, X does expose a general-purpose, non-partner-gated endpoint for this: `GET /2/users/by/username/{username}` returns a user's id, name, username, and (with additional fields requested) description and other public profile fields for any public account, not just the authenticated user's own.
This is a "non-owned" read, billed at the standard $0.005 per resource under pay-per-use, with no Enterprise or partner approval required for the lookup itself.
That is a real difference from LinkedIn, which has no self-serve profile-lookup path at any price.
The catch is the same developer-app and pre-purchased-credit setup as option 1, for a feature that duplicates what screenshot capture already does today at zero marginal API cost.

**Product fit:** Neutral to weak.

- Technically feasible without partner approval, unlike LinkedIn.
- But it adds a paid, metered dependency to replace a capture flow (screenshot -> vision extraction -> derived URL) that already works today for free, and that already derives the profile URL directly from the handle without any API call.
- Only worth revisiting if a user pastes a bare `@handle` with no screenshot and product wants to auto-fill a name/bio from that alone; even then, the added cost and X-account dependency buys little over asking the user to paste a screenshot instead.

**Recommendation:** Skip for now.
Keep the model: user (or screenshot OCR) supplies the memory; the link is a door out, not a data source in.

### 4. Sign in with X (OAuth via Clerk)

**What it is:** Auth only - name, handle, and (as of a 2026 Clerk update) email of the *signed-in user*.

**Effort:** Low.
Clerk fully supports X/Twitter's v2 OAuth flow; enabling it is a dashboard toggle (SSO connections > Add connection > X/Twitter), and Clerk development instances can turn it on with zero additional configuration using Clerk's shared credentials.
Production would need Euno's own X developer app and redirect URI, matching the LinkedIn OIDC option's effort level.

**Product fit:** Neutral.
Helps people who live in X identity sign up faster; does not help recall, and does not by itself grant any scope to read followers/following (that would need a separate, explicitly-requested OAuth scope and the same paid API path as option 1).

**Recommendation:** Optional growth/auth experiment.
Not required for X *product* value.
Prefer after Google (or whatever is already primary) is solid, same as the LinkedIn recommendation.

### 5. Post to X (write endpoints)

Out of scope for Euno's one job (hand back a person so you can reach out yourself).
Posting is also billed per-post under pay-per-use ($0.015, or $0.20 if the post contains a link), which only reinforces that this is not a fit.
Skip.

### 6. Deepen X-aware capture (no X API)

Unlike the LinkedIn deep-dive, this is a short section, because the gaps LinkedIn has do not exist for X today.

Checked and already closed:

1. **URL:** the handle is visible on nearly every X screenshot, so `deriveProfileUrl("x", handle)` already fires and renders a link pill; there is no derive-URL hole to close the way there is for LinkedIn.
2. **Copy:** `PLATFORM_LABELS` already maps `x` to `"X"`, so the triage card does not show the raw lowercase enum value.
3. **Extraction:** the vision prompt is platform-generic, but X profile screenshots typically carry a single bio line rather than LinkedIn's separate title-plus-company structure, so there is less to gain from platform-specific prompt tuning here than there was for LinkedIn.

The one real residual gap: `normalizeUrl` and `deriveProfileUrl` both assume a clean handle once `@` is stripped, which already covers the common cases (mangled OCR handles get URL-encoded rather than breaking the link).
No further work is indicated here; this option is effectively "keep doing what already works."

---

## Fit against Euno principles

| Principle | X followers/following import (API or export) | Capture + derived link (current behavior) |
| --- | --- | --- |
| Hand back the person, not a dashboard | Fails - imports a broadcast/interest graph, not people met | Passes |
| No CRM / scoring | Borderline - looks like audience import | Passes |
| Private, user-authored memory | Contested - X's data + metered API dependency | Passes |
| MVP "link + context" loop | Overbuilds, and needs a paid API to even resolve names | Extends existing loop for free |

---

## Decision matrix

| Option | Feasible without a paid X API? | Product fit | Recommend |
| --- | --- | --- | --- |
| Followers/following import (API) | No (metered, and owned-reads discount status for third-party apps disputed) | Weak | No |
| Followers/following export (archive) | Yes, but only numeric IDs, no names | Weak | No |
| Handle/URL -> profile enrich via API | Yes (self-serve, unlike LinkedIn), but duplicates free capture | Neutral / low value | No |
| Post to X | Yes, but billed per post and out of scope | Fails | No |
| Sign in with X (Clerk) | Yes | Auth only | Optional later |
| X-aware capture (current behavior) | Yes, already shipped | Strong | **Yes - keep as is** |

---

## Suggested next step

No engineering work is indicated for X capture; it already derives profile URLs from screenshots without any manual paste step, ahead of LinkedIn's current state.
Treat any "Connect X" marketing language as **auth**, not **import**, and do not revisit the followers/following import question until X's pay-per-use pricing and its third-party owned-reads scope stop changing underneath developers mid-quarter.

## Sources

- [X API pay-per-usage pricing and credits (docs.x.com)](https://docs.x.com/x-api/getting-started/pricing) - official pricing page: $0.005 per post read (2M/month cap before Enterprise), $0.015/$0.20 per post created, $0.001 per resource for Owned Reads, full Owned Reads endpoint list including `GET /2/users/{id}/followers` and `GET /2/users/{id}/following`
- [Announcing the Launch of X API Pay-Per-Use Pricing (X Developer Community)](https://devcommunity.x.com/t/announcing-the-launch-of-x-api-pay-per-use-pricing/256476) - official February 2026 pricing-change announcement
- [X API Pricing Update: Owned Reads Now $0.001 + Other Changes Effective April 20, 2026 (X Developer Community)](https://devcommunity.x.com/t/x-api-pricing-update-owned-reads-now-0-001-other-changes-effective-april-20-2026/263025) - confirms the pricing model was still being revised months after its February 2026 launch
- [Owned Reads $0.001 rate not applied to bookmarks endpoint - billed at $0.005 instead (X Developer Community)](https://devcommunity.x.com/t/owned-reads-0-001-rate-not-applied-to-bookmarks-endpoint-billed-at-0-005-instead/263311) - documented billing inconsistency in the new pricing model
- [Owned Reads and Lists (X Developer Community)](https://devcommunity.x.com/t/owned-reads-and-lists/263489) - open developer question on Owned Reads scope
- [Questions about recent price changes (X Developer Community)](https://devcommunity.x.com/t/questions-about-recent-price-changes/263353) - developer confusion over whether the Owned Reads discount applies to third-party/multi-tenant use
- [User lookup by username, GET /2/users/by/username/{username} (X Developer Platform docs)](https://developer.x.com/en/docs/twitter-api/users/lookup/api-reference/get-users-by-username-username) - general-purpose public profile lookup endpoint, not partner-gated
- [How to access and download your X data (X Help Center)](https://help.x.com/en/managing-your-account/accessing-your-x-data) - official steps for the personal data archive export
- [How to download your X archive and Posts (X Help Center)](https://help.x.com/en/managing-your-account/how-to-download-your-x-archive)
- [Twitter: How to archive your following/followers data (GitHub Gist, robinst)](https://gist.github.com/robinst/31bee24c7c2e08194645dba5eec2e41e) - first-hand technical account confirming the archive's follower/following files contain only numeric account IDs, not usernames
- [Add X/Twitter v2 as a social connection (Clerk Docs)](https://clerk.com/docs/guides/configure/auth-strategies/social-connections/x-twitter) - Clerk's X/Twitter OAuth v2 support, including zero-config development instances
- [X social connection improvements (Clerk changelog, 2026-03-06)](https://clerk.com/changelog/2026-03-06-x-social-connection-improvements) - email address now returned on X sign-in
- In-repo: `PRODUCT.md`, `docs/superpowers/specs/2026-07-15-euno-mvp-design.md`, `src/lib.ts`, `convex/openaiClient.ts`, `src/CaptureTriage.tsx`
