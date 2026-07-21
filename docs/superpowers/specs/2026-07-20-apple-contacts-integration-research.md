# Apple Contacts Integration Research

Date: 2026-07-20
Status: Research / recommendation
Audience: Product + engineering decision on whether and how Euno should integrate with Apple Contacts (macOS/iOS) to import or seed a user's own address book

## Verdict

**Do not build an Apple Contacts import, in any form, right now.**
Not because it is technically hard - unlike LinkedIn, there is no partner gate and no API to be denied.
The user already owns this data outright and can get it out of Apple's ecosystem in one click.
The reason to skip it is the same reason the MVP design already gives: a flat contact list has no "how I met this person" story, and that story is the entire product.
MVP design explicitly lists "Apple Contacts or any bulk import" as out of scope for the MVP, and separately lists "Apple Contacts import to seed the back catalog" under Future ("not now, but the model allows it").
This research confirms that framing was right, and explains why the two "obvious" web APIs for reaching into a user's contacts do not even change the calculus.

**There is no direct API path available to a web app at all.**
Euno is a Vite/React web app, not a native iOS/macOS app, so it cannot call Apple's `Contacts` framework (`CNContactStore`) - that framework only exists inside apps built with Apple's SDKs and reviewed through the App Store or a signed native build.
A web page has no equivalent entry point into Apple's Contacts database.

**The one web standard that sounds relevant - the W3C Contact Picker API - does not actually solve this problem for Euno's users.**
It is unsupported in Safari on both macOS and iOS as of today (still hidden behind an experimental flag), and even where it is enabled (Chrome), it reads the OS's own contacts store on Android, not Apple's iCloud/Contacts.app data.
For an Apple-first, Safari-using audience, this API is close to a no-op.

**The only mechanism that actually works today is the same shape as the LinkedIn CSV path: a user-initiated export file.**
Apple's Contacts.app, iCloud.com, and the Shortcuts app can all export a user's own contacts as a vCard (`.vcf`) file, which a web app can accept as an upload with zero API, zero partnership, and zero App Store review.
It is fully feasible.
It is also exactly the bulk-import shape the product has already decided to defer.

**Optional later, if product ever revisits "seed the back catalog":** vCard upload is the realistic route in, not a picker or a native framework.
It should be scoped as a deliberate staging/triage flow (one row at a time, context required before a row becomes a real person) rather than a one-click "import all," so it does not regress into the empty-contact-list problem Euno exists to avoid.

---

## What Euno already does with contacts-shaped data

Unlike LinkedIn, Apple Contacts has no existing surface area in the product at all - there is no platform enum, no derive-URL logic, and no capture path that touches a user's address book.

| Surface | Behavior today |
| --- | --- |
| Add a person | Manual only: name by hand, then an optional link and free-text context (`src/lib.ts`, `CaptureTriage.tsx` flow). No contact-list read of any kind. |
| Screenshot capture | `openaiClient.ts` platform enum covers social platforms (e.g. `linkedin`); there is no `contacts` or `vcard` platform, and no code path reads a device address book. |
| Bulk import | None exists anywhere in the codebase (`grep` for `vcard`, `vcf`, `navigator.contacts`, `CNContact` all return nothing in `src/` and `convex/`). |
| MVP scope | `docs/superpowers/specs/2026-07-15-euno-mvp-design.md` explicitly lists "Apple Contacts or any bulk import" under "Explicitly out of scope for the MVP," and lists "Apple Contacts import to seed the back catalog" under "Future (not now, but the model allows it)." |

So this is not a gap to close inside an existing capture flow (as LinkedIn was); it is a standalone product question about whether to build a new import surface at all.

---

## Integration options evaluated

### 1. Native access via Apple's Contacts framework (`CNContactStore`)

**What people usually mean:** "Euno reads straight from the Mac/iPhone address book, like a native app would."

**API reality (2026):** `CNContactStore` (and the older Address Book / `EventKit`-adjacent APIs it replaced) is a framework inside Apple's native SDKs (Swift/Objective-C, iOS/macOS/watchOS).
It is not exposed to web content in any browser, on any platform.
There is no bridge, polyfill, or browser extension mechanism that grants a web page this API - the only way to call it is to ship a native app (or a WKWebView-hosted hybrid app) built and signed with Apple's tooling, with the `NSContactsUsageDescription` permission and, per WWDC 2024, Apple's newer "Contact Access Button" / limited-access picker UI for partial grants on iOS 18+.

**Product fit:** Not evaluable on fit alone - it is a platform mismatch.
Euno is a web app; building a native shell purely to reach this one API would be a large, disproportionate engineering investment (a real iOS/macOS app, code signing, App Store review, ongoing maintenance) for a feature the product has already deferred.

**Recommendation:** Not a real option while Euno stays a web app.
Revisit only if Euno ever ships a native client for reasons unrelated to this feature.

### 2. W3C Contact Picker API (`navigator.contacts.select(...)`)

**What people usually mean:** "The web page itself asks the user to pick contacts, like a native picker, no export file needed."

**API reality (2026):** The Contact Picker API is a real, user-consent, per-selection API - the user explicitly picks which contacts to share and which fields (`name`, `email`, `tel`, `address`, `icon`) to expose; there is no persistent or background access.
It is a W3C Working Draft on the Recommendation track, not yet a finished standard.

Browser support has not materially changed in the direction Euno would need:

- Chrome supports it, but only on Android - Chrome for Android (from Chrome 80+, full support from 112) reads Android's own on-device contacts database.
Chrome's own developer docs describe it purely as a mobile/Android capability with no ChromeOS, Windows, or macOS support.
- Safari does not support it on macOS or iOS as of mid-2026.
It remains behind an experimental flag (Settings > Safari > Advanced > Feature Flags on iOS, or Develop > Experimental Features on macOS Safari), not enabled by default.
- Firefox does not support it on any platform.

The practical consequence for Euno specifically: even in the one browser/OS combination where this API works, it is reading Android's contacts store, not Apple's iCloud/Contacts.app data.
It cannot deliver "Apple Contacts" to a Mac or iPhone user in Safari at all, because Safari does not ship the API.
There is effectively no live path from this API to the data this research is about.

**Product fit:** Would have been the *best* fit of any option here if it worked on Apple platforms - it is inherently one-contact (or a few)-at-a-time, user-initiated per use, and closer in spirit to Euno's "search a contact, or add a new one" loop than a bulk dump.
It sidesteps the "empty back catalog" problem by design, since nothing is added until the user actively picks someone while adding a person.

**Recommendation:** Not usable today for Euno's Apple-first audience.
Worth re-checking if Safari ever ships it (there is no committed timeline), at which point it would be worth revisiting as a "prefill a new person's name/email/phone from a picker" affordance on the existing manual-add flow - not as bulk import.

### 3. vCard (.vcf) export and upload

**What people usually mean:** Same goal as options 1 and 2 (seed my people list from my address book), reached through the export feature every Apple user already has instead of an API or picker.

**How it works today:** A user can export their own contacts as one or more vCard (`.vcf`) files through several Apple-native paths, all requiring no developer account, no API key, and no Euno-side integration with Apple at all:

- **Contacts.app on Mac:** select contacts, right-click, "Export vCard."
- **iCloud.com:** Contacts > select all (or some) > Actions/Share menu > "Export vCard," which bundles the selection into a single `.vcf` file.
  iCloud.com contacts export is web-only (desktop/tablet browser), not available from the mobile Safari UI.
- **iPhone/iPad Contacts app:** Select All > Share > Save to Files, saving a `.vcf` to Files/iCloud Drive, which can then be picked up by any file-upload input.

A basic vCard export commonly includes name, phone number(s), email address(es), and postal address; it does not include notes, photos, or birthdays in the default export path.
There is no "how we met" field - the file is a contact list, not a memory, exactly as the sibling LinkedIn research describes the CSV connections export.

**Feasibility:** Fully feasible, today, with zero Apple involvement on Euno's side.
Parsing vCard is a solved, well-specified format (RFC 6350); a file-upload input plus a small parser is the entire engineering lift.
This is meaningfully *easier* than the LinkedIn CSV path, since the export is instant (no wait for a data-export job) and requires no account settings hunt.

**Product fit:** Weak, for the reason the MVP design already states outright.

- PRODUCT.md: "A relationship cannot be captured by data plus a friend list," and Euno's anti-CRM, anti-bulk-import stance.
- MVP design: "Apple Contacts or any bulk import" is explicitly out of scope for the MVP, and is filed under Future, not under "do this now."
- A vCard dump is a phonebook, not a memory: rows have no context, no "how did I meet them," and would land in Euno as a wall of names with nothing to search by beyond the name itself - the opposite of the fragment-of-memory recall loop the product is built around.

**Recommendation:** Not now.
This is the technically realistic route in if product ever deliberately reopens "seed the back catalog" (the Future item already names this exact feature).
If that happens, design it as a staged, one-at-a-time promotion flow (surface candidates, require the user to add context before a row becomes a real person) rather than a one-click "import all 800 contacts," so it does not regress into an empty social-graph dump.

### 4. Shortcuts-app automation bridge (webhook)

**What people usually mean:** "Something more automatic than manually exporting and uploading a file, but without building a native app."

**API reality (2026):** Apple's Shortcuts app (iOS/iPadOS/macOS) has built-in "Find Contacts" and "Get Contacts from Input" actions that can read the device's Contacts store under the Shortcuts app's own permission grant, and a "Get Contents of URL" action that can POST JSON (with custom headers, e.g. a bearer token) to an arbitrary endpoint.
In principle, a user could install a Euno-authored Shortcut that reads their contacts and POSTs them to a Convex HTTP action, without Euno ever touching Apple's native APIs directly and without any App Store review, since Shortcuts are user automations, not distributed apps.

**Feasibility:** Technically plausible, but this only moves the bulk-import problem around - it replaces "export a file, then upload it" with "install and run a Shortcut," which is a heavier ask (users have to trust and install a third-party automation, and Euno would own an API-token-issuance and Shortcut-distribution/support surface) for the same end result as option 3.
It does not solve anything option 3 does not already solve, and it adds meaningfully more engineering and support surface (token auth, Shortcut versioning, "why did my Shortcut break after an iOS update" support load).

**Product fit:** Same as option 3 - still a bulk contact dump with no "how we met" context, just with extra steps to build.

**Recommendation:** Skip.
If bulk import is ever revisited, plain vCard upload (option 3) gets to the same place with far less engineering and no bespoke automation to maintain.

### 5. Enrich an existing person from Apple Contacts data

**What people usually mean:** The Apple-Contacts analogue of "paste a LinkedIn URL and Euno fills in details" - looking up or enriching *someone else's* record.

**API reality:** This does not apply the way it did for LinkedIn.
Apple Contacts is inherently local, per-device, per-user data with no server-side directory or lookup API - there is no way to "enrich a person" from Apple Contacts because there is no arbitrary-person lookup surface at all, only the current user's own address book.
The closest real-world equivalent (someone shares a vCard for themselves, e.g. via AirDrop or a signature block) is just a specific instance of option 3 (one vCard, one contact) rather than a distinct integration.

**Recommendation:** Not a meaningful category for Apple Contacts; fold any "someone sent me their vCard" case into the general vCard-upload path (option 3) if that is ever built, rather than treating it as enrichment.

---

## Fit against Euno principles

| Principle | Bulk import (vCard, Shortcuts, hypothetical picker) | Status quo (manual add + link/context) |
| --- | --- | --- |
| Hand back the person, not a dashboard | Fails - produces a list of names with no story | Passes |
| No CRM / scoring | Borderline - looks like a contact-list dump | Passes |
| Private, user-authored memory | Neutral - data is the user's own, but arrives with zero authored memory attached | Passes |
| MVP "link + context" loop | Overbuilds; skips the context step entirely | Matches the loop as designed |
| "Bring a fragment of memory, get back the person" | Inverted - starts from a full address book, not a fragment | Matches as intended |

---

## Decision matrix

| Option | Feasible without partnership/approval? | Product fit | Recommend |
| --- | --- | --- | --- |
| Native `CNContactStore` access | No (requires a native app Euno does not have) | N/A - platform mismatch | No |
| W3C Contact Picker API | Yes on Chrome/Android only; no on Safari/macOS/iOS | Would be strong if it worked on Apple platforms | No - not usable for this audience today |
| vCard (.vcf) export + upload | Yes, fully self-serve, no partner/API needed | Weak (bulk, no context) | No, not now |
| Shortcuts-app webhook bridge | Yes, but higher build/support cost than vCard | Weak (same as vCard, plus extra ops burden) | No |
| Enrich a person via Apple Contacts | Not applicable (no lookup surface exists) | N/A | No |

---

## Suggested next step

No engineering work now.
Treat this research as confirming, not overturning, the MVP design's existing call: "Apple Contacts or any bulk import" stays out of scope, and "Apple Contacts import to seed the back catalog" stays on the Future list, not the near-term one.

If product ever deliberately reopens that Future item, come back to this document first: the route in is vCard upload (option 3), not a picker or a native framework, and it should be designed as a context-required staging flow rather than a one-click import, in the same spirit as the LinkedIn research's recommendation to keep Euno capture-and-context-first rather than seed-the-catalog-first.

## Sources

- [Contact Picker API - MDN](https://developer.mozilla.org/en-US/docs/Web/API/Contact_Picker_API) - API shape, requested fields, "not Baseline" support warning
- [Contact Picker API - W3C Working Draft](https://www.w3.org/TR/contact-picker/) - Recommendation-track Working Draft, not yet a finished standard
- [A contact picker for the web - Chrome for Developers](https://developer.chrome.com/docs/capabilities/web-apis/contact-picker) - describes support as Android-only, reading the Android contacts store
- [Navigator API: contacts - Can I use](https://caniuse.com/mdn-api_navigator_contacts) - Safari (desktop and iOS) and Firefox unsupported; Chrome supported
- [Interacting with Contacts on the Web](https://marcusv.me/blog/native-contact-picker-safari/) - documents Safari's experimental-flag-only support
- [What PWA Can Do Today: Contact picker](https://whatpwacando.today/contacts) - live feature-detection page confirming unsupported-by-default status on the fetching device
- [CNContactStore - Apple Developer Documentation](https://developer.apple.com/documentation/contacts/cncontactstore) - native Contacts framework, native apps only
- [Meet the Contact Access Button - WWDC24](https://developer.apple.com/videos/play/wwdc2024/10121/) - iOS 18 limited-access contacts picker, native-app-only feature
- [Import, export, or print contacts on iCloud.com - Apple Support](https://support.apple.com/guide/icloud/import-export-and-print-contacts-mmfba748b2/icloud) - vCard export steps and desktop/tablet-only limitation for iCloud.com
- In-repo: `PRODUCT.md`, `docs/superpowers/specs/2026-07-15-euno-mvp-design.md`, `src/lib.ts`, `convex/openaiClient.ts`, `src/CaptureTriage.tsx`
- Sibling doc (unmerged branch `cursor/linkedin-integration-research-05dc`): `docs/superpowers/specs/2026-07-20-linkedin-integration-research.md`
