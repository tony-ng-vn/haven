# Capture Input Research: Making Saving People Effortless

Date: 2026-07-26
Status: Research / recommendation
Audience: Product + engineering decision on how Haven captures people (the input side of the core loop), before the Phase 2 screens are designed

## Verdict

**Input is four different problems with four different deadlines, and the current "screenshot now, upload and annotate later" flow fails because it bundles them into one deferred session that memory research says arrives too late.**
Separate them: capture the *pointer* in the moment with zero thought, make the *trigger* automatic so an "upload" step never exists, ask for the *human memory* the same evening or next morning while it still exists, and run *enrichment* asynchronously behind a confirmation gate.

The recommended decisions, each argued below:

1. **Kill the upload step.** Haven scans the photo library for new screenshots on next open (iOS persistent change history makes this reliable with no background tricks) and auto-queues the ones that look like profiles. Screenshotting stays the zero-thought event habit; "go home and upload" stops existing.
2. **Add a share extension.** Instagram, LinkedIn, and X all share a canonical profile URL to the system share sheet, which also closes the known LinkedIn gap (the vanity slug never appears in screenshots). Zero permissions, highest-fidelity pointer.
3. **Add one-tap voice capture.** Ten seconds of speech ("Mai, LinkedIn recruiter, Spain shirt, talked soccer") becomes a structured person. Fully buildable offline-first on iOS 17/18; the original audio is kept forever as the source of truth.
4. **Prompt for the human context the same evening or next morning - never at random across days.** Conversational recall is ~10% same-day and ~4% at a month; a day-3+ prompt hits an empty head. Reject the random-queue idea for initial capture.
5. **Keep the spreading instinct, but aim it at retention.** Spaced "do you still remember?" reviews at ~1 week and ~1 month after capture are evidence-backed (testing effect), because by then Haven holds the answer to reveal. That is the legitimate home of "ask across time".
6. **Ship the proactive channel Apple-native.** Communication-style local notifications can render exactly like a message from a person and deep-link into an app-owned chat capture surface - the Friendy inversion with no third party. The iMessage relay stays a founder-personal tool, not product foundation.
7. **Enrichment: extraction yes, scraping no, web search maybe.** Keep interfaze for vision extraction of the user's own screenshots. Never fetch LinkedIn (Proxycurl was litigated to death in 2025; Apple guideline 5.1.1(viii) reads directly against compiled personal data). Grounded web search with a confirm card is the one defensible lane, gated behind user initiation.
8. **Add "met at" to the model.** Time and place of the capture moment are the retrieval cues people actually use, they cost nothing to record, and Humin proved both the query and the mistake of collecting it via always-on sensing. One tap per event (event mode), or calendar correlation, never a per-person form field.

This directly answers mvp-design's Concerns 1-3 (manual-add friction, dynamic-context friction, deferred-review fragility).

---

## The framing: four problems, four deadlines

| Stage | What it is | Deadline | Mechanisms |
| --- | --- | --- | --- |
| Pointer | Who is this person (identity anchor) | At the event, but thoughtless | Screenshot, shared profile URL, spoken name, new contact |
| Trigger | Getting captures into Haven | None - must be automatic | Photo-library catch-up, share extension, contacts change history |
| Human memory | Context no machine can know | Same evening; hard ceiling ~24-48h | Voice one-liner at capture; per-event triage batch |
| Enrichment | Machine-addable facts | Whenever, async | Vision extraction (exists), confirm-gated web search |

The current design makes the user do all four in one sitting, later, per person.
Every stage has a cheaper home.

---

## What the graveyard teaches

A survey of ~20 personal-CRM and people-memory products (Clay/Mesh, Dex, folk, Monica, Covve, Blinq, Humin, UpHabit, Rewind/Limitless, Plaud, mymind, and the 2020 graveyard list Dex maintains) found that nobody has built a durable standalone consumer business in this category, and input strategy is the strongest predictor of outcome.

- **Capture tied to an existing physical ritual survived best**: Blinq's QR at the handshake, Covve's card scan (Covve repositioned its whole company around the scan moment), mymind's screenshot-of-anything.
- **Passive sync kept products alive but not independent**: Clay executed it best in class, stayed niche, and sold to Automattic; its founders' words are Haven's thesis verbatim: "Your homegrown solution grows stale almost instantly when you start adding info to it manually."
- **Manual-entry products died, pivoted to B2B, or persist as unfunded passion projects.** Dex's own guide: "If saving a contact takes more than a few seconds ... you will eventually stop doing it."
- **Ambient hardware captured everything and still failed the people layer**: Limitless could not attribute conversations to person entities without manual speaker labels; Rewind's postmortem shows capture without reliable retrieval churns.
- **Humin is the essential precedent**: it validated the exact retrieval query ("met last week", "met in San Francisco") and validated auto-capturing time/place at save - and died of its delivery costs (always-on location, replace-your-dialer). Capture the envelope at the moment of capture only.
- **The open ground**: mymind proves screenshot-plus-AI-parse is a paid consumer behavior, and no shipping product applies it to people. "Screenshot a profile, get a person" appears to be unowned.

Two traps with names on them: do not build the spine on scraped auto-sync (platform-risk treadmill, fills fields nobody searches by), and do not let capture require discipline (forms, required fields, weekly rituals).

---

## The evidence on timing (why the random queue loses)

The memory literature is unambiguous, and it splits the proposal cleanly in half.

**Initial capture must be early.**
Ebbinghaus-curve replications (Murre & Dros 2015) put the majority of total loss inside day 0-1.
Free recall of conversation content is ~10% even minutes-to-hours later (Stafford & Daly 1984) and ~4% at a month (Stafford et al. 1987).
Peripheral detail - what they wore, the specific thing they said - decays faster than gist (Sacripante et al. 2022), and the encoding cues that let you retrieve a name die first of all (Groninger & Guardado 2012).
Sleep consolidates what was encoded before it (Payne et al. 2012), which favors a same-evening write-down, and next-morning full-day reconstruction is a validated method (Kahneman's Day Reconstruction Method).
A prompt at day 3-7 lands after the steep loss is complete.

**Delay helps only after capture.**
The testing effect is real (Roediger & Karpicke 2006), and spaced retrieval was validated on name learning specifically (Landauer & Bjork 1978) - but failed retrieval only helps when the correct answer follows (Kornell, Hays & Bjork 2009).
For "how we met", the user is the only holder of the answer: a failed recall at day 5 strengthens nothing and teaches the user that Haven asks unanswerable questions.
Once the context is stored, Haven holds the answer, and optional reveal-after-recall reviews at ~1 week and ~1 month sit in the optimal spacing band (Cepeda et al. 2008).

**The prompt schedule this implies:**

- One local notification per event-day, not per person: "5 people from tonight - add the story while it's fresh", at a quiet evening hour or Duolingo-style at the hour the user was free yesterday; next morning as fallback; one final quiet retry the next evening; then stop.
- The triage session is one bounded, finishable batch per event: card stack, 5-10 cards, machine-known cues on the card (photo, event, place, time - recognition cues outlive recall), two asks max, one-tap skip.
- Untouched people quietly enter a "faded" state - still searchable, still holding everything the machine knows - with a one-tap "let it go".
  No global queue screen, no unresolved counts, no badges, no streaks: every queue product that let the backlog become visible became a guilt object (Anki's backlog guidance, read-it-later postmortems); Arc's auto-archive is the calm precedent.
- Apple's own Journal ships exactly this two-channel model (moment-triggered suggestions plus reflection at a predictable user-chosen time) and nothing in the ESM/EMA compliance literature supports randomized timing for logging prompts.

---

## Capture surfaces, ranked (iOS specifics verified against Apple docs)

**1. Share extension (build early).**
All three platforms share a profile URL through the system sheet (LinkedIn documents it; Instagram and X verified by observation - confirm payloads with a TRUEPREDICATE dev build).
Zero permissions, works on every target iOS version, receives a clean URL instead of pixels to OCR, and the same extension accepts screenshots shared from Photos.
This also closes the LinkedIn slug gap the platform research flagged: the shared URL carries the vanity slug the screenshot never shows.

**2. Screenshot catch-up ingestion (the upload-step killer).**
iOS 16+ persistent change history (PHPersistentChangeToken + fetchPersistentChanges) tells Haven, on next open, exactly which assets appeared since last open; combine with the Screenshots smart album subtype and run the existing extraction pipeline on candidates.
No background execution needed; the deferred user action shrinks to "open the app".
Costs: effectively requires full photo-library access (limited access hides new screenshots), the iOS 17+ prompt shows counts and the system periodically re-confirms full access, and App Review guideline 5.1.1(iii) prefers pickers - so ship a real justification screen and a picker fallback.

**3. One-tap voice capture (the dynamic-memory input).**
Architecture, all GA and cited in the voice report: one tap -> AVAudioRecorder writes a local .m4a that is never deleted -> immediate on-device SFSpeechRecognizer pass (requiresOnDeviceRecognition) biased with contextualStrings from the user's own saved people -> person created instantly from the local transcript -> a queue drains on connectivity: cloud STT with the people graph as keyterms (Deepgram/AssemblyAI keyterm prompting or OpenAI prompt) plus one small-model structured-outputs call producing {name, company, role, city, note}.
The weakest link is Vietnamese names inside English speech - no vendor claims that case - and the mitigations are exactly Haven's unfair advantages: the audio is the truth (nothing is lost to a bad transcript), the saved-people graph is the bias list (diacritics included), and iOS 26's SpeechTranscriber adds first-class on-device vi_VN with free re-transcription of old clips.
Hands-free reality check: a one-breath "Hey Siri, tell Haven ..." is not implementable; the real paths are Action Button + Dictate Text into an App Intent (iOS 17), or AudioRecordingIntent one-press background recording (iOS 18+, requires a Live Activity).

**4. Event mode (the "met at" solution).**
One press (Action Button, iOS 18 Control, or App Shortcut) starts a Live Activity (8h active cap) holding a capture button on the Lock Screen all evening; every capture inside the window inherits the event name, place, and time.
This is Humin's envelope without Humin's always-on cost, and it doubles as the trigger for the same-evening triage notification when the activity ends.
Calendar correlation (Friendy already proved it on macOS; EventKit on iOS) can prefill the event name.

**5. Contacts change detection (the safety net).**
CNChangeHistoryFetchRequest (iOS 13+) supports "you added Mai to Contacts last night - remember how you met?" on next open.
The old research's "no API path" verdict was a web-app-era conclusion; native iOS dissolves it.
Caveats: a historically awkward Swift surface (ObjC shim may be needed) and iOS 18 limited-access mode hides contacts the user has not granted - full access is what makes the feature real.

**6. JournalingSuggestions (enrichment garnish, not capture).**
Strictly a user-driven picker (the app never sees unpicked suggestions, cannot prompt proactively); iOS 17.2+.
Useful inside next-morning triage as "attach who you were with / where you were", nothing more.

---

## The proactive channel: Friendy's inversion, without the relay

The pattern worth keeping from Friendy is the inversion - the system notices something happened (screenshots taken, contact added, event ended) and opens the conversation.

- **In the product:** iOS Communication Notifications (iOS 15+) render a local notification like a message from a person - avatar, sender name, "Who did you meet at Demo Night?" - and deep-link into a chat-style capture screen Haven owns.
  Reliability 5/5, privacy 5/5, cost zero, platform risk none, and it works identically in Vietnam.
  Dot (New Computer) proved the app-owned proactive-chat UX; Poke (100M+ messages in three months, acquired by Cognition, July 2026) proved users accept - like - an assistant that initiates.
- **The iMessage relay:** "Spectrum" is Photon (photon.codes); the vendor ecosystem (Photon, Sendblue, LoopMessage, BlueBubbles self-hosted) is real but unofficial - Mac fleets running real Apple IDs, meaning every capture would transit a third party's machines, E2EE terminating at the vendor.
  That structurally contradicts "private memory layer", Apple has enforcement precedent (Beeper Mini) plus a new sanctioned lane (it approved Poke as the first AI agent on Apple Messages for Business, June 2026), and the audience math fails in Vietnam (iMessage is iPhone-only in an Android-led market).
  Verdict: keep Friendy on Photon's free tier as the founder's personal tool and test bench; do not build the product on it; if a texting channel ever proves core, the sanctioned Messages-for-Business lane now demonstrably exists.
- **Vietnam:** WhatsApp is a 6-7% channel there, Telegram is government-blocked, Zalo is 79-85%.
  A Zalo Official Account bot is the only messaging lane that will matter for a Vietnamese audience - explicitly unresearched, queued as follow-up.

---

## Enrichment: the lane that survives scrutiny

- **Keep interfaze for extraction only.**
  interfaze.ai is JigsawStack's OpenAI-compatible multimodal API (YC P26, credible self-published screenshot-OCR benchmarks, ~sub-cent per image).
  Do not let its auto-invoked web search/scrape tools become the lookup layer: they cannot be steered per-request, billing converts infrastructure to opaque token counts, and its documented LinkedIn-scraping-with-residential-proxies posture makes it a Proxycurl-shaped legal dependency for exactly that use.
- **LinkedIn fetching is a no-build, on four independent axes.**
  No API exists for this; the vendor supply chain is being litigated to death (Proxycurl: sued January 2025, dead by July 2025, permanent injunction, mandated data deletion and customer notification; ProAPIs sued October 2025; LinkedIn's win record is perfect); LinkedIn's User Agreement 8.2.4 reaches data *buyers*, not just scrapers; and Apple's guideline 5.1.1(viii) - "Apps that compile personal information from any source that is not directly from the user or without the user's explicit consent, even public databases, are not permitted" - describes the feature almost word for word.
  If the user wants LinkedIn detail, deep-link to the profile; never fetch or store it server-side.
- **Grounded web search is the defensible lane, if shipped carefully.**
  One "enrich this person" action (search + a few page reads + synthesis) costs $0.006-0.045 at 2-10s across Perplexity Sonar (one call, citations built in), Gemini 2.5 Flash grounding (free at Haven's volume), Exa's people category, or Tavily.
  The engineering problem is wrong-person risk, not plumbing: a bare name identifies nobody (tens of thousands of collisions for common names), so the query is "name + company/school", fields require the name plus one corroborating signal on the source page, every field carries a source URL, and "no confident match" is a first-class, common, honest outcome.
  Ship the confirmation gate with v1 of the feature, not later: candidate card (photo, headline, source links, fetched-at) with Confirm / Not this person / Search again; auto-attach never happens on a name alone; suggested vs confirmed data stay visually distinct (Apple's "Siri Found in Mail" pattern); per-item dismiss and a global off switch.
  Those mitigations are load-bearing for App Review, and a one-time privacy-counsel pass is warranted before this ships.

---

## The recommended capture architecture

Four layers, replacing the single deferred session:

1. **Moment (zero-thought, offline):** screenshot (unchanged habit); share-to-Haven; hold-to-talk voice one-liner; all inside an optional event mode that stamps "met at".
2. **Net (automatic):** photo-library catch-up finds the screenshots; the share extension and voice notes arrive directly; contacts change history catches exchanged numbers; nothing here is a user obligation.
3. **Refine (while fresh):** one communication-style notification per event-day, same evening or next morning; a bounded per-event card stack; voice or text one-liner per card; skip freely; untouched people fade gracefully; optional spaced "still remember?" reviews at ~1 week and ~1 month.
4. **Machine time (async):** vision extraction on capture; embeddings (already live); confirm-gated web-search enrichment on demand.

**Build-order suggestion for Phase 2** (the backend for save/search shipped in PR #78; the capture pipeline and captures table already exist from the web era):

1. Manual add + notes editor + offline pending queue (already the Phase 2 plan) - with the voice one-liner button included from day one, since audio-first capture is the single biggest friction cut.
2. Screenshot catch-up ingestion feeding the existing extraction pipeline, plus the per-event triage batch (this is the roadmap "swipe review queue" pulled forward with an evidence-backed schedule).
3. Share extension.
4. Event mode + evening/morning notification.
5. Spaced reviews, JournalingSuggestions garnish, enrichment card - in whatever order dogfooding demands.

**Schema implications (additive, when each lands):** an `events` notion (or met-at fields: name, place, time) on people; audio attachment storage id on people (must join the orphan-sweep reference checks, same as photos); capture provenance (screenshot / share / voice / contact / manual); a pending/triage/faded state distinct from the current captures table's pending; per-event grouping for the batch.

## Open questions

1. Photo full-access acceptance: will the target user grant it after a good justification screen? Design the picker fallback regardless.
2. Empirically confirm share payloads from Instagram/LinkedIn/X with a TRUEPREDICATE dev build before committing UX.
3. iOS floor: staying at 17 keeps everything above except AudioRecordingIntent and Controls (18+) - is an 18 floor acceptable by Phase 2 ship time?
4. Photon free-tier inbound media (for Friendy personal use): verify screenshots and voice notes actually arrive; fall back to Sendblue or BlueBubbles if not.
5. Zalo Official Account API research for the Vietnam channel.
6. Privacy counsel pass before web-search enrichment ships (GDPR Article 14, Apple 5.1.1(viii) posture).

## Sources

Competitors and graveyard: nesslabs.com/clay-featured-tool; getdex.com/guides/finding-the-right-personal-crm/; getdex.com/blog/personal-crm-in-2020-20-startups-apps-and-failed-attempts/; news.ycombinator.com/item?id=25270001; techcrunch.com/2016/03/29/tinder-acquires-humin-as-it-broadens-out-from-dating-creates-sf-office/; 148apps.com/reviews/humin-review/; andrewschreiber.substack.com/p/an-early-adopters-thoughts-on-rewindais; techcrunch.com/2025/12/05/meta-acquires-ai-device-startup-limitless/.
Memory and timing: journals.plos.org/plosone/article?id=10.1371/journal.pone.0120644 (Murre & Dros); Stafford & Daly 1984 and Stafford et al. 1987 (Human Communication Research); pmc.ncbi.nlm.nih.gov/articles/PMC9944610/ (Sacripante); journals.sagepub.com/doi/10.1111/j.1467-9280.2006.01693.x (Roediger & Karpicke); web.williams.edu/Psychology/Faculty/Kornell/Publications/Kornell.Hays.Bjork.2009.pdf; journals.sagepub.com/doi/abs/10.1111/j.1467-9280.2008.02209.x (Cepeda); science.org/doi/10.1126/science.1103572 (DRM); docs.ankiweb.net/deck-options.html; resources.arc.net (auto-archive).
iOS surfaces: developer.apple.com/documentation/photokit/phpersistentchange; developer.apple.com/videos/play/wwdc2022/10132/; developer.apple.com/documentation/uikit/uiapplication/userdidtakescreenshotnotification; developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ (share extensions); developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system; developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities; developer.apple.com/documentation/appintents/audiorecordingintent; developer.apple.com/documentation/journalingsuggestions; developer.apple.com/documentation/contacts/cnchangehistoryfetchrequest; developer.apple.com/app-store/review/guidelines/.
Voice: developer.apple.com/documentation/speech (SFSpeechRecognizer, contextualStrings, SFCustomLanguageModelData, SpeechTranscriber); apple.com/ios/feature-availability/; developers.deepgram.com/docs/keyterm; assemblyai.com/docs (keyterms, supported languages); developers.openai.com/api/docs/guides/speech-to-text; granola.ai/security; voicenotes.com; help.limitless.ai/en/articles/10761340-pendant-storage.
Messaging channel: photon.codes (Spectrum, pricing, platform); sendblue.com (pricing, safety, webhooks); loopmessage.com; bluebubbles.app; macrumors.com/2023/12/10/apple-confirms-it-shut-down-beeper-mini/; register.apple.com/messages; appleinsider.com/articles/26/06/04/first-ai-agent-for-messages-business-chat-approved-by-apple; techcrunch.com/2026/07/24/why-cognition-bought-poke-ai-personality-is-becoming-a-competitive-advantage/; developer.apple.com/documentation/usernotifications/implementing-communication-notifications; rfa.org/english/vietnam/2025/05/23/vietnam-telegram-ban/; vietnamnet.vn/en/zalo-used-by-85-of-vietnamese-surpassing-global-apps-2406688.html.
Enrichment: interfaze.ai (docs, pricing, leaderboards); nubela.co/blog/goodbye-proxycurl/; law.com/therecorder/2025/01/27/linkedin-suit-says-millions-of-profiles-scraped-by-singapore-firms-fake-accounts/; cdn.ca9.uscourts.gov/datastore/opinions/2022/04/18/17-16783.pdf (hiQ); linkedin.com/legal/user-agreement (8.2.4); learn.microsoft.com/en-us/linkedin/ (Profile API); developer.apple.com/app-store/review/guidelines/ (5.1.1); docs.perplexity.ai/getting-started/pricing; ai.google.dev/gemini-api/docs/pricing; exa.ai/pricing; library.me.sh/hc/en-us (Mesh merge/duplicates); support.apple.com/guide/mail/use-information-found-in-mail-in-other-apps-mlhleed80167/mac.
Repo grounding: docs/superpowers/specs/2026-07-20-*-integration-research.md (LinkedIn, Instagram, X, Facebook, Apple contacts - the platform no-build verdicts and capture-first framing); docs/superpowers/specs/2026-07-20-namedrop-contact-sync-research.md; github.com/tony-ng-vn/Friendy (the inversion pattern and Spectrum transport).
