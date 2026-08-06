# Changelog

What changed in Haven, newest first, written for someone using the product
rather than reading the diff.

Entries begin at v0.2.0. Everything before that lives in the git log and the
pull requests, which is where it is easiest to read anyway.

## v0.51.0

2026-08-06

**Web**

- inhavens.com now opens on the glass-artwork landing -- the one that was previewed at landing2 -- instead of the waitlist page.
- The iPhone waitlist has its own address now, inhavens.com/waitlist: the landing's "Join the iPhone waitlist" button goes there, and old #/ios and #/join links redirect there too.
- The Your Sky download page has its own address now, inhavens.com/sky: the landing's other button goes there, and old #/sky links redirect there too.
- Every other old page address, including the retired /landing preview, now lands on the front door instead of a broken or orphaned page.
- The waitlist page no longer carries the "Building your own map already? Try Your Sky for Mac" footnote -- it asks one thing now, joining the list.

---

## v0.50.0

2026-08-06

**Web**

- The Sky download page no longer feels squeezed into a narrow phone-width column on a computer screen -- it now uses the space a real desktop page has, with a wider reading column and more generous spacing the wider the window gets.
- That page now makes its pitch before its ask: the hero carries just the headline and the honest install notes, and the one Download for Mac button sits at the end, after the steps and the privacy promises.
- The Your Sky / iPhone / Sign in links that used to sit in the top corner of every page are gone everywhere, not just on some pages -- each page's own buttons already point you where you need to go, and the Haven wordmark alone gets you back to the front door.
- The Haven mascot in that top corner is noticeably bigger now, and it sits truly centered next to the wordmark -- it used to look faintly off-center no matter what, because the mascot artwork itself was trimmed unevenly; that is fixed at the source now, not papered over with CSS.
- The front door at inhavens.com is the iPhone waitlist again -- the same page the "join the iPhone waitlist" links already pointed at. The landing-page hero that had been living at the root is still there to compare, now at its own /landing address, alongside a second landing concept previewed at landing2 -- neither is what a new visitor meets first anymore.
- The two hero buttons ("Sky app, coming soon" and "Join the iPhone waitlist") now line up exactly level with each other everywhere they appear together -- they used to sit 4 pixels apart.

---

## v0.49.0

2026-08-05

**Web**

- The landing2 concept page now has the same living night sky as the main landing -- drifting stars and the wandering constellation -- behind its copy on the left, fading away before the artwork begins on the right so the two never overlap.
- The Haven mascot icon now sits next to the wordmark in landing2's nav.

---

## v0.48.0

2026-08-05

**Web**

- A polished preview of the Haven landing now lives at inhavens.com/landing, side by side with the unchanged default: its own custom typeface, and a calmer, more deliberate feel to every button press, hover, and scroll-in -- the default landing at the root is untouched, so this is a fair comparison rather than a replacement.
- The landing2 concept page now shows the owner's own generated glass artwork directly, in place of the earlier CSS attempt at drawing broken glass -- the real image fused into the page rather than approximated by it.

---

## v0.47.0

2026-08-04

**iOS**

- Connecting LinkedIn, Instagram or X on the contact question now fills in your real, proven address automatically, the same way X's always has -- LinkedIn no longer needs a guessed slug checked by hand unless the connection itself fails.
- Instagram can now be connected at all, for creator and business accounts; a personal account is told so before it ever gets stuck, both on the row itself and if the connection is tried anyway.
- A connected account fills in your photo again, the same as it always did -- carried over to the new connection method, not lost with the old one.
- Sharing a link from Safari can now find Haven in the share sheet. It was registered and installed correctly the whole time; the rule that was supposed to let it in required every single item Safari attaches to a share -- the page's own text and a snapshot, not just the link -- to be something Haven explicitly claimed, so one unclaimed extra silently hid it every time.
- Sharing a profile from apps that send it as a message rather than a link -- LinkedIn's own app among them -- now reaches Haven too, with the profile link found inside the message.
- The Lock Screen widget actually renders now, instead of the system's own grey "please try again" placeholder -- it was missing one required setup step, invisible until an owner actually put it on a real Lock Screen -- and it now has a wider version with Haven's name on it, for the slot people actually add it to next to the clock, not just the small circle.
- When Ask cannot answer, Haven now says it is taking a little coffee break and will come back soon, instead of a flat error line.
- The People tab is now named for you -- "Tony's Haven" rather than a bare count of who you have saved -- and reads "Your Haven" until your name has loaded.
- The People tab, a person's own page, and My Card now keep listening for changes for as long as you are on them, instead of quietly going silent after sitting still for a few seconds. That silent cutoff is why a person you just added used to show up in Search well before they showed up on the People tab that led you there.
- The People tab no longer shows a long scroll bar running most of the way down the screen for just a handful of saved people.
- Haven now shows itself the moment you tap the icon, instead of a blank screen while it quietly finished setting up sign-in behind the scenes first -- that setup still has to happen, it just no longer holds up the first thing you see.
- The moment behind that first screen is the night sky now, not a plain loading spinner -- Haven waits on the sky everywhere else, and the launch screen is no longer the one exception.
- My Card now has a Sign out button, quieter than and above Delete your account: until now the only way off an account on this phone was deleting it.

**Backend**

- Haven now asks Composio, not Clerk, for what LinkedIn, Instagram and X actually know about someone's account, because Composio's managed connections hand back real profile data Clerk's own connections never surface.
- Deleting your Haven account now also disconnects LinkedIn, Instagram and X at Composio, so the OAuth access you granted them does not keep working under an account that no longer exists.

---

## v0.46.0

2026-08-03

**iOS**

- The People list can load past its first fifty again, and the share sheet's offline copy of your directory loads at all: both were asking the server for rows in a shape it silently refused, so scrolling to the bottom of a longer list, or opening the share sheet before ever launching the app, went nowhere.
- Haven no longer hangs on a dead connection, and this reaches further than it first looks. Saving a note about someone, asking Haven who fits a need, and syncing a profile shared in while offline could each get stuck waiting forever for a reply that was never coming -- the note trapped in an editor with no way to save or leave it, the ask screen with no way back to search, and every capture silently going nowhere until the app was force-quit. Chasing that down found the guarantee underneath all of Haven's saves: every one of them trusted a shared "give up after a few seconds of silence" rule that was not actually being kept, so editing your card, answering an onboarding question, and editing someone you had already saved could each have hung the same way without ever showing why. All of it now genuinely gives up and offers to try again, rather than only appearing to.
- The sky revealed at the end of onboarding is now the sky that person keeps. It used to show the placeholder figure the questions were seeded with, before the card had a permanent address; the reveal now draws the same constellation My Card, Connect and the public web card all already show.
- The faint drifting dust behind every screen now pauses while a sheet is open over it, the same way the sky and the card's own drift already do -- less battery spent animating something nobody can see.
- The welcome screen now offers Sign up and Sign in as their own doors, rather than one button that guessed which you meant. Signing in with Apple is set aside for now, since the production accounts plan only has room for three outside logins and Google, LinkedIn and X fill them.
- Every dialog Haven opens over the app now carries a visible close button in the top corner, so leaving one no longer depends on already knowing you can swipe it away.

---

## v0.45.0

2026-07-31

**Web**

- inhavens.com now opens on a full-screen hero instead of a small corner of text: the same drifting, constellation-lit sky that used to live behind the waitlist now fills the entire page, not just the first screen, so scrolling past the hero never hits flat dark. Star clusters appear and drift across the sky on their own from time to time, on any device; on a mouse or trackpad, dragging across it follows and lights up the figure the headline "Your people are a constellation." is describing. Two calls to action sit side by side under it -- Try Your Sky for Mac, which you can try today, and join the iPhone waitlist, for the phone app still in development. Further down the page, a live sample sky you can click into and explore for yourself (entirely invented people), a short word on what the iPhone app will do, and a quiet footer. Anyone who had a link to the root expecting to join the waitlist still finds it on the first screen, not below a scroll.
- Haven now has a download page for Your Sky, its Mac companion app, at inhavens.com/#/sky. It walks through the whole flow -- download, authorize access on your Mac, click "Map relationships" -- and says exactly what happens to your data: the analysis runs on your Mac, your messages are never uploaded, and the map is built from who you talked to and how often, never from what you said.
- Haven for iPhone now has its own page at inhavens.com/#/ios, carrying the waitlist signup that used to live at the root. It introduces what the iPhone app will do -- one profile, connecting with someone in one tap, finding anyone later by any detail you remember -- and says plainly that it is still in development. A quiet link at the bottom of the form points to Your Sky, for anyone who wants a Mac companion in the meantime.
- The landing page, Your Sky, and the iOS page now share a quiet footer linking to the Privacy Policy, Terms of Service, and Support, plus a copyright line -- the same documents the signed-in app already links to, now reachable from every public page as well.
- A second, experimental landing concept is live at inhavens.com/#/landing2 -- not linked from anywhere on the site, reachable only by typing the address. The whole screen is one pane of dark broken glass over a hidden nighttime world: a moon over mountains, a warm cabin window among trees, handwritten memories, small gold particles. Resting your pointer over it (or tapping it on a touch screen) lets the glass pieces drift gently apart so the world underneath shows through the cracks. The same Your Sky and Haven for iPhone introductions and buttons sit on top of it. It is one of two directions being weighed for the front door, not a replacement for the page above.

---

## v0.43.1

2026-08-03

**CI**

- The daily check on Haven's live sign-in settings now actually runs. It had failed within seconds of starting every morning since the day it was written, so it had never once looked at anything -- a check that has never passed and a check that broke overnight are indistinguishable in a list of red marks, which is how it went unnoticed for six days. It found two real things on its first honest run, both since fixed: Clerk, the service behind signing in, was still calling the app "Euno" on its own screens and in every sign-in email, and it was still sending people to its own hosted sign-in pages rather than Haven's. The second one is the failure that broke sign-in in production once before -- Haven's own code has been overriding it since, so nobody was stuck, but the setting behind it had never been corrected. Both halves of that guard are now in place, and the check passes for the first time.
- The bot that opened an automatic pull request every morning with one suggested improvement has been removed. It had been failing daily rather than proposing anything.

---

## v0.43.0

2026-07-29

**Web**

- A person's page now shows the person. Their photo, what they do, where they are, and what they say about themselves were all being sent to the browser and quietly dropped -- the page had their name, the month you added them, and the boxes you type in, and nothing else. It now opens the way their card does on the iPhone: their photo above their name in their own sky, their role, company and city on one line under it, and their headline below that.
- If a photo cannot load, the page simply shows no photo. A person without one is an ordinary person, and a broken-image square is not an answer.
- The page now says whether somebody is still connected to you on Haven. A small "Connected" tag sits under their name. If the connection ended -- they left Haven, or one of you disconnected -- it reads "No longer connected", and one line explains what that means for everything above it: this is the last thing their card said, and it will not change again. Without that, a frozen page and a person who never updates anything look identical.
- The note you keep about somebody is now called "What you remember", the same thing the iPhone app calls it, instead of "Private context" -- a name nothing else in Haven ever used. It also says how the note is read: one line per thing, because each line is searchable on its own.
- The platform you marked as how somebody prefers to be reached now leads their list of ways to reach them, instead of sitting wherever it happened to be saved.

---

## v0.42.0

2026-07-29

**Web**

- The Feedback button and the sheet it opens now belong to Haven. They were arriving in the widget's own colours -- a white pill on the night sky, and a white sheet with a purple Submit -- because nobody had ever told it what Haven looks like. It reads the night, the ink, and Haven's own corners now. It stays an internal-only button, and it is still temporary.

---

## v0.41.0

2026-07-29

**Web**

- A handle you save for somebody now shows up on their page, as a row you can tap. Adding "mai.makes" on Instagram used to look like it vanished: the page only ever showed the free-text link box, so the handle was saved and never seen again. The rows sit above the link, one per platform, and each opens the right place -- Instagram, X, LinkedIn, Telegram, a WhatsApp chat, or the phone dialler. If you marked one as how they prefer to be reached, that row says so. A platform Haven has never heard of still shows the handle; it just does not pretend it can open it.
- "Where you know them" is now a short list instead of a text box. Typing it by hand meant "WhatsApp" and "whats app" quietly became two different platforms, and neither one linked anywhere. The list is the same one the iPhone app offers, and the handle field follows it -- picking Phone or WhatsApp asks for a number, with the number keypad on a phone and no at-sign in front of it.
- Pasting somebody's profile link into the handle field now saves just the handle. Paste "https://instagram.com/mai.makes" and Haven keeps "mai.makes", the way the iPhone app already did, so the row it gives you back opens their profile instead of a dead address. If you paste a link Haven cannot find a handle in -- one of LinkedIn's mobile share links, say -- it says so instead of saving something that opens nowhere.
- Adding someone no longer collides with the screen behind it. On a first-run empty sky, the form used to grow straight down through "No one here yet"; that message steps aside while you are filling the form in, since you are already doing what it asks.
- One thing to do at a time: the floating "Capture someone new" button steps aside while the add form is open, instead of offering a second way to start the same errand.

---

## v0.40.0

2026-07-29

**Web**

- The web is now clearly the place you go to look at your network, not a second copy of the app. Meet, which exchanged contact with someone standing next to you, and the Love Alarm radar have both left the website: those are things you do with a phone in your hand, and they belong in the iPhone app. What the web is for stays exactly as it was and now has room to breathe -- your sky, search, adding someone by typing their name, your public card, and the sign-in and legal pages.
- The add form no longer borrows the Meet panel's look. It has its own, so changing one can never quietly redraw the other.
- Nothing was deleted from your account. Every username, connection, and radar setting is untouched on the server, and the iPhone app still uses all of it.

---

## v0.39.0

2026-07-29

**Web**

- A person's constellation is now the same figure everywhere it appears -- on the atlas, on their page, and on the card link you share -- and it now matches the iPhone app exactly. Every screen was minting a sky from a different piece of somebody, so one person could have three, and the card you handed a stranger did not look like the card on your phone.
- Renaming someone no longer scrambles their stars. A person's sky is drawn from who they are rather than what you have called them, so editing a name leaves the figure alone.

---

## v0.38.0

2026-07-29

**Web**

- The web app now wears the same night as the iPhone app. The dusk palette from iOS -- night ground, cream primary button, star-amber accent -- replaces the old blue-and-gray look, and the web is dark-only like the app instead of following the system theme. A test now pins every token to the iOS values, so the two platforms cannot quietly drift apart again.
- People's names are set in the app's serif everywhere one appears, matching the iOS rule that the serif is reserved for people.
- Every screen now sits on the same ground as iOS: night easing into dusk, with the ember glow rising off the bottom edge.
- Clicking into the search field or a form field no longer draws a hard blue rectangle inside the rounded control; keyboard focus shows a soft star-tinted ring on the control itself.
- The waitlist's stars and its join button glow warm amber and cream instead of the retired blue.

---

## v0.37.0

2026-07-29

**Web**

- The site's content security policy is now enforced rather than merely reported. It had been in report-only mode since it was written, which means it had never actually blocked anything -- a missing entry showed up as a console message nobody was watching instead of as a problem.
- The feedback widget can reach its own service. It posts to a hosted service on a different Convex deployment, which the policy had never named; under report-only that broke nothing, and turning enforcement on without this would have broken it silently for the only people who can see the widget.

**CI**

- Pull requests that cannot change the website no longer build one. Most changes here are to the iOS app or the backend, and each was still producing a full web deployment: of the last forty merges, thirty-three built a bundle that had not changed, and those builds were three quarters of the account's daily deployment budget -- which is what ran it out. Production still builds every time, because that build is what ships the backend.
- Signing in on the web works again. It had been bouncing between Haven and a Clerk-hosted page forever, never showing the form -- Clerk was told sign-in lived somewhere else and kept sending people there, and that page kept sending them back. Haven now tells Clerk where its own sign-in is.
- inhavens.com/signin, /sign-in, /signup, /sign-up and /login all reach the sign-in screen. Every one of them used to show the waitlist, so typing the most obvious address suggested Haven had no way in.

**CI**

- A daily check now reads the live Clerk configuration and fails if it disagrees with the app. The sign-in loop was invisible to every test in the repo because the fault was in a dashboard rather than in a file, and only appeared on the production account -- this is the part that can see that.

---

## v0.36.0

2026-07-29

**iOS**

- Haven is now an iPhone app, in portrait, and says so. It had been telling the App Store it ran on iPad in every orientation -- not a decision anybody made, just the setting nobody filled in. Nothing in the app adapts to a bigger screen or a sideways one, so it was claiming more than it could back. Nothing changes for anyone on an iPhone.

---

## v0.35.0

2026-07-29

**Web**

- Haven's sign-in screen can now load its own provider logos and avatars. The security policy the site sends listed every host except the one Clerk serves images from, which would have left the sign-in buttons blank the moment that policy was enforced.

**iOS**

- The App Store version is now 1.0.0. It was 0.1.0, which would have told anyone reading the listing that the first release was a beta.

**Docs**

- The remaining work before an App Store submission is written down where it can be worked through: name reservation, three developer-portal capabilities, the Team ID, screenshots, and the privacy answers. All of it is dashboard or device work, and none of it is a code change.
- Two decisions surfaced that nobody had made: Haven currently tells the App Store it is an iPad app, which nothing in the design ever asked for and no one has tested, and the notes App Review reads have not been written.

---

## v0.34.0

2026-07-29

**iOS**

- The App Store build now signs in against Haven's own production accounts system instead of the development one. Until now a release build would have refused to start at all -- deliberately, so it could never quietly send real people to a development sign-in that caps how many accounts can exist.

---

## v0.33.0

2026-07-29

**Web**

- Haven has a support page at inhavens.com/support. It answers what to do when you cannot sign in, exactly how to delete your account and everything in it, whether the people you write notes about can see them (they cannot), and how to reach a person about anything else.

**Docs**

- The App Store Support URL now points at that page instead of the marketing site, which is what a reviewer expects to find behind it.

---

## v0.33.0

2026-07-29

**Web**

- The site's content security policy is now enforced rather than merely reported. It has been in report-only mode since it was written, which means it has never actually blocked anything -- a missing entry showed up as a console message nobody was watching instead of as a problem. Two entries were missing when this was turned on, and both were found by the audit rather than by anyone noticing.
- The feedback widget can reach its own service again. It posts to a hosted service on a different Convex deployment, which the policy had never named; under report-only that broke nothing, and enforcing it without this would have broken it silently for the only people who can see the widget.

---

## v0.32.1

2026-07-29

**Backend**

- Sharing a profile for someone whose handle you have saved on two different people now says so instead of quietly filing the share under whichever one you saved first.

---

## v0.32.0

2026-07-28

**iOS**

- Three screens that had no way to be looked at now have one: the two handle editors and the welcome screen. Nothing about them changed; they simply could not be reviewed before a build, which is how a screen ends up shipping wrong.

---

## v0.31.0

2026-07-28

**Docs**

- The frontend plan is closed out: every unit ticked, the exit criteria audited line by line with the evidence for each, and the three places the plan's own inventory turned out to be wrong recorded rather than quietly worked around.
- The tracker's "Needs you" is now the whole of what is left, and says so: a dashboard, a key, a device, or App Store Connect. Anything in it that could be written in code is in the wrong section.
- The App Store compliance checklist stops saying Haven has no camera code. It has, since connect scanning landed, and the permission string and the privacy manifest's deliberate silence about it are both recorded where a reviewer would look.

---

## v0.30.0

2026-07-28

**Docs**

- Everything the App Store asks for in words is drafted and in the repo: subtitle, description, keywords, category, age rating, the privacy answers, and the five screenshots to capture, in the order that makes the argument. It can be argued with in a diff now instead of typed into a web form at submission time.

**iOS**

- The Clerk production swap is written down as a procedure beside the key it changes: four edits that have to land together, and what breaks if one is missed.

---

## v0.29.0

2026-07-28

**Web**

- The site's content policy now names both the development and the production Clerk instances. The production publishable key is already live on Vercel, so the next production build loads Clerk from a domain the policy did not mention; listing both means whichever key a build compiles in, the policy covers it.

---

## v0.28.0

2026-07-28

**iOS**

- A name, company or role that is too long now says so while you are typing it, naming the limit. It used to save, fail on the server, and come back as "check your connection" -- which was a lie about a problem sitting in front of you.

---

## v0.27.0

2026-07-28

**iOS**

- Three pieces of text that were failing contrast at the bottom of the screen now read there: the search field's label on People, the placing line under a person an ask names, and the line that says a connection has ended. The page darkens toward the bottom, and all three could end up in the dark half.
- The reason an ask gives for each match is now the brightest thing in the row, rather than the line above it being the dimmest. Same hierarchy, made by lifting what matters instead of sinking what does not.

---

## v0.26.0

2026-07-28

**iOS**

- Turning the card over twice quickly no longer hitches. The flip is the one thing in Haven a finger can catch mid-flight, and it was animated on a curve that restarts from a standstill when you interrupt it.
- Saving somebody by hand, writing a note, and connecting to another person now each land with the same light tap that answering an onboarding question does. All three were silent, which made the app's most deliberate actions feel like nothing had happened.

---

## v0.25.0

2026-07-28

**iOS**

- Answering an onboarding question no longer pauses. The star came on in about four tenths of a second and the app then waited another four and a half tenths before moving, twice over, on the one moment the whole flow is built around.
- Your address can be shared from your card. Turn the card over and the share button beside the title sends the page your code opens, for the times you are not standing in front of somebody.

---

## v0.25.0

2026-07-28

**iOS**

- A person you connected to on Haven now says so, and their screen follows their card: change your job and everyone connected to you sees it, without either of you doing anything.
- A connection that ended says that too. If somebody deletes their Haven account, or one of you disconnects, their screen keeps everything you wrote and says plainly that what it shows is the last thing their card said and will not change again -- rather than looking like somebody who simply never updates anything.
- You can disconnect without deleting them. You keep them and your notes; their card stops updating here, and the note the two of you wrote together goes with the connection.
- On a connected person, the fields that are theirs say they are theirs, so an edit that would be overwritten on the next read is not offered as though it would stick.

---

## v0.23.0

2026-07-28

**iOS**

- A Haven code scanned with the phone's own camera, or a Haven link tapped in a message, now opens Haven instead of Safari -- straight onto the card it names, with Connect one tap away. Your own address opens your code instead, because offering to connect you to yourself is a dead end.

**Web**

- The site now tells iOS which of its addresses belong to the app. Its own pages -- the landing page, privacy, terms, and every name held back for the site -- are excluded by name, so tapping those still opens the web page they are.

---

## v0.22.0

2026-07-28

**Docs**

- The frontend plan's tracker now says what is built and what is waiting, the device ledger names every check that needs a real phone and what each one is for, and three places where the plan's own inventory turned out to be wrong are written down rather than quietly worked around.
- Two decisions that had been made by simply not building anything -- no screenshot triage on the phone, and the onboarding sky staying as it is -- are written down as decisions, so they can be argued with rather than discovered later.
- The plan now says where each of its own exit criteria actually stands, and what the evidence for each one is worth.

---

## v0.21.0

2026-07-28

**iOS**

- Haven now teaches you where it lives. A fresh install puts it at the very back of the share sheet, behind More, which is exactly where nobody finds it -- and no app is allowed to move itself. The People screen offers to walk you through it: a picture of where Haven should sit, three steps, and a real share sheet to do them on, with a practice person to save at the end.
- The suggestion only appears while you have nobody saved, and it takes no for an answer.

---

## v0.20.0

2026-07-28

**iOS**

- Your directory no longer stops at fifty people. It loads more as you scroll, and the count at the top stops saying "50+" once it has them all -- before this it said "50+" to somebody with three hundred people and never stopped saying it.

---

## v0.19.0

2026-07-28

**iOS**

- You can connect to somebody in person. A scanner in the top corner of People reads the code on the back of their card, shows you whose card it is, and one tap puts each of you in the other's directory. Haven's backend has done both sides since the connect work landed and nothing in the app ever asked it to.
- If you were already connected it says so rather than pretending something happened.
- Their address can be typed instead of scanned, for a phone whose camera you would rather not turn on and for reading one out across a table.
- The camera is only ever asked for at the moment you point it at a card, and nothing it sees is kept.
- The People screen's empty state now says how to fill it.

---

## v0.18.0

2026-07-28

**Web**

- The constellation on the landing page still forms on a very wide screen. Haven caps how many stars it draws, so past about 2560 pixels the lens had fewer and fewer of them to join and the figure thinned to a line or two; it now reaches further out to find a constellation instead.
- A long handle on a public card no longer pushes the platform name off its row. It truncates, which is what it was always meant to do.
- A photo that will not load leaves an ordinary card behind rather than a broken-image icon, which was the first thing a stranger could have seen after scanning somebody's code.

---

## v0.17.0

2026-07-28

**iOS**

- A question you skipped during onboarding stays skipped. It used to be remembered only on the phone you skipped it on, so reinstalling Haven, or signing in on a second phone, asked you everything again.
- Onboarding also stops restarting itself. Clearing your city on My Card used to drop you back into the questions on the next launch, because an empty field and a question nobody had asked looked identical from the app's side.
- Connecting X or LinkedIn now brings your photo across. The picture the provider already has of you lands on your card and lights its star, so the photo question answers itself. A photo you chose yourself is never replaced.

---

## v0.16.0

2026-07-28

**iOS**

- Your card now shows the address it points at, under Your address, and you can change it. Until now Haven picked one for you when you signed up and there was no way to see it, let alone pick a different one.
- If the address you want is taken, Haven says so and offers ones that are free right now, built from your own name. It does not guess for you.
- The editor says what changing it costs before you change it: the code on the back of your card opens that page, and the old address stops working.

---

## v0.15.0

2026-07-28

**iOS**

- Search results open the person. Tapping a name in the results, whether you got there by typing or by pinning a company, city or role chip, now opens their screen with their handles and your note. Until now a result was a dead line of text.
- So do the people an ask names, direct matches and bridges alike.
- Coming back leaves your search exactly as it was: the same words, the same chips, the same answer still on screen.

---

## v0.14.0

2026-07-28

**Web**

- Pull request previews no longer deploy the backend. Every preview build ran `convex deploy` against the shared deployment, so several pull requests updated at once raced each other and some deploys simply failed -- including one that changed nothing but documentation. Only production deploys Convex now, which is what the repo's own rules already said.

---

## v0.13.0

2026-07-28

**iOS**

- A person's screen finally shows how to reach them. Their handles are listed with the one you marked primary first, and tapping any of them opens that app: Instagram, X, LinkedIn and Telegram open the profile, a phone number starts a call, a WhatsApp number opens the chat. Haven was already being sent all of this and was throwing it away.
- Their photo is on the screen too, next to their name.
- You can change any of it. An Edit button opens their details: name, photo, city, company, role, and every way to reach them, each edited on its own the way your own card already worked.
- You can delete somebody. It is behind a confirmation that says what goes with them, because what you wrote about them is the part nobody else has a copy of.
- A page a capture recorded for them is shown only when it is not already one of their handles, so one way to reach somebody is never listed twice.

---

## v0.12.0

2026-07-28

**iOS**

- You can add someone by hand. The Add someone button on People has been sitting there disabled since the screen was built; it now opens a sheet asking their name, one way to reach them, and one line about them, and saves them to your directory.
- The handle can be on any of six platforms, not just the three Haven reads shares from: Instagram, X, LinkedIn, phone, WhatsApp and Telegram. Paste a profile link or type the handle; Haven shows you what it will actually store before you save.
- Adding someone works with no signal. The save is written to your phone and sent when there is a connection, the same way a profile shared into Haven is, so nobody is ever lost to a basement.
- If the handle you type is already on somebody in your directory, Haven says who before you save, and your note is added to them rather than filing a second copy of the same person. If the name matches somebody instead, it offers them and lets you decide.

---

## v0.11.0

2026-07-28

**CI**

- The iOS test job runs one at a time across every branch. There is one Mac and one simulator on it, and two runs landing together fought over the same simulator device -- one of them died during startup with an error that reads exactly like a real test failure and is not one. It cost two false reds in a day.

---

## v0.10.0

2026-07-28

**Backend**

- Love Alarm now forgets you were in a room. Presence expired after two minutes and stopped being visible, but the record that you had been there stayed until you deleted your account; it is now deleted when it expires.
- A screenshot capture no longer files someone's linked account as their job title. On Instagram and TikTok, which have no headline, that line is read as the bio it actually is -- so searching a company name stops turning up people whose only connection to it was a link in their bio.
- Your name, city, company, role and handles now have a length the server agrees with, on your own card and on people you save. The limits are the ones the design settled on; before this the app capped nothing and the server accepted anything.

---

## v0.9.0

2026-07-28

**Backend**

- A connection who changes jobs, moves city or changes their name is now findable under the new details rather than the ones they had the day you met. Their row in your directory used to keep whatever their card said at that moment, so search and the filter chips answered with a version of them that no longer existed.
- Their card now shows how to reach them: the handles they publish, under any you saved yourself, and the platform they said they prefer. Before this, a person you met in one tap showed only their Haven address.
- Your directory can tell you which people are Haven connections, and which ones used to be. A contact that stopped following someone's card -- because they left Haven, or because one of you disconnected -- now says so instead of quietly going still.
- You can end a connection without deleting the person. Disconnecting drops the live link and the note the two of you wrote together, and both of you keep your own notes, photo and memory of each other.
- Deleting a contact you were connected to no longer leaves the other person's copy pointing at a connection that no longer exists.
- Deleting your account still leaves your billing history behind, on purpose: it is the record of money that moved, and it answers refund questions after the account is gone.

---

## v0.8.0

2026-07-28

**iOS**

- The privacy policy and terms of service are now one tap away on the welcome screen, before you sign in, instead of only appearing once you already have an account.
- Both pages now open inside Haven rather than handing you to Safari. You read them over the app and close them with Done, and whatever you were in the middle of, including a sign-in you had not finished, is still there when you come back.
- A menu in the top corner of People holds them too, so the policy is somewhere you can find it from the app itself, not only from the screen about your own card.

---

## v0.7.1

2026-07-28

**iOS**

- The rows under your card now say what they do. Every one of them opens something and none of them showed it; a filled field has a chevron, and an empty one says "Add" where the value would be, so a field you have not filled in no longer looks like one you have.
- The platform marks on the card fit it. They were sized like buttons they are not, and four of them were slightly too wide for the card they sit on, on every iPhone. They also grow with your text size now, which they never did.
- Scrolling no longer slices the card off along an invisible line. It passes under the title bar instead.
- The ACCOUNT and LEGAL headings are readable where they actually sit. The page darkens toward the bottom, which is exactly where those headings are, and they were failing contrast there.
- "Delete your account" is coloured as the warning it is, rather than looking like one more field to edit.
- When a change to your card fails to save, the message that says so is coloured as a warning. It was written to be one and rendered in the same grey as a hint.
- A long name at a large text size no longer prints over your constellation or squeezes it out of existence. On an iPad the card stops growing instead of becoming taller than the screen.

---

## v0.7.0

2026-07-28

**iOS**

- Your card has a back now. Tap it and it turns over to show the code someone else points a camera at, along with your Haven address underneath in case they cannot scan it. The screen brightens on its own while the code is up, because a dim screen is the most common reason a scan fails.
- The separate beacon screen is gone, and so is the QR button that used to sit in the People toolbar. There is one card and you turn it over, rather than two places showing the same thing. The Lock Screen widget still works and now opens your card already turned to the code.
- The card itself lies flat and drifts gently side to side, with its sky sliding the other way behind it, so it reads as an object held against the night rather than a panel printed on the screen. It has a printed double rule around its edge, and the reveal at the end of onboarding now shows exactly the same card My Card does.

---

## v0.6.0

2026-07-28

**iOS**

- Search can now be asked a question instead of given a keyword. Type what you actually need -- "anyone who knows databases" -- and Haven reads everyone you know and answers in their own words, quoting the note that made each person a match.
- It also answers the harder question: when nobody fits directly, it names who could introduce you, marked as a bridge and with its reasoning shown, rather than quietly passing them off as a match.
- If what you asked was too vague to answer, Haven asks you one question back instead of guessing, and you can answer it without starting over.
- Asking is a button, not something that happens as you type. Searching is instant and free; asking reads your whole network through a model, so it only ever runs when you ask it to.

**Backend**

- An answer now says who each person is, not just which record they are, so nothing has to look them up one by one to show you a list.

---

## v0.5.0

2026-07-28

**iOS**

- Haven is now in the iOS share sheet. Open somebody's profile in Instagram, LinkedIn or X, tap Share, tap Haven, and they are saved -- with one line about how you met, asked right there while you still remember it, rather than later when you have to go and find them first.
- Sharing works with no signal, and before you have even signed in. The sheet writes to the phone and closes; the next time you open Haven it sends everything that was waiting. There is no queue screen and no badge, because a capture that landed is just a person in your directory.
- The sheet knows who you already know. Share somebody already on file and it says so and adds your note to them rather than making a second copy of them. Share a second platform for somebody and it offers to add it to them, and asks rather than assuming, because two people really can share a name.
- A LinkedIn share fills the name in for you from the profile link. Instagram and X do not hand over a name, so that field stays empty rather than being filled with a handle, which looks like a name without being one.
- You can share a screenshot to Haven too, which means importing one works before Haven has ever asked for your photo library.

---

## v0.4.0

2026-07-28

**iOS**

- Tapping someone in your directory now opens them, which it never did before. Their card is at the top, and under it is a box for what you remember about them.
- That box is the first place in the iPhone app where you can write anything about a person. Until now Haven could search your notes and reason over them, and there was no way to write one.
- The box says to keep one line per thing, because each line is searchable on its own -- "met at the Founder Inc dinner" and "works on an infinite-context database" find them separately.

---

## v0.3.0

2026-07-28

**Backend**

- Two Haven users who meet in person now become a real mutual connection, not just two contacts who happen to have each other's handle. One tap from either side, no request-and-accept step, and both directories update at once.
- A connected person's card stays theirs. Open them and you see whatever they have on their profile right now, so someone changing jobs updates in your directory without either of you doing anything, while the notes and photo you added stay yours.
- Someone you connected with now lands in your directory under their real name instead of their handle, and is findable by their company, role, and city straight away.
- Connecting no longer writes a fake "met through Haven" note. That line was about to become a memory on every connection, which would have filled memory search with the same meaningless sentence over and over.
- If someone deletes their Haven account, your contact for them stays, frozen at what you last saw, like a phone contact. Their live card leaves with them; your memory of them is yours.
- Deleting a connected person now clears the connection and the note the two of you shared, instead of leaving them behind to reappear if you ever connect again.
- Deleting your account now removes your notes as well. They were being left behind, which meant an account deletion that did not delete everything.

**Web**

- The meet-exchange screen now creates a real connection, and tells you when you were already connected.

---

## v0.2.0

2026-07-28

**Backend**

- Haven can now tell whether a signed-in person is a paying subscriber, and that answer comes from Stripe rather than from anything the app or a browser claims. Subscriptions that start, change, lapse, or get cancelled in Stripe are picked up on their own. Nothing is charged yet, and there is no checkout screen: this is the groundwork one will sit on.

---
