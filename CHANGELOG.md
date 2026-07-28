# Changelog

What changed in Haven, newest first, written for someone using the product
rather than reading the diff.

Entries begin at v0.2.0. Everything before that lives in the git log and the
pull requests, which is where it is easiest to read anyway.

## v0.18.0

2026-07-28

**iOS**

- Your directory no longer stops at fifty people. It loads more as you scroll, and the count at the top stops saying "50+" once it has them all -- before this it said "50+" to somebody with three hundred people and never stopped saying it.

---

## v0.17.0

2026-07-28

**iOS**

- You can connect to somebody in person. A scanner in the top corner of People reads the code on the back of their card, shows you whose card it is, and one tap puts each of you in the other's directory. Haven's backend has done both sides since the connect work landed and nothing in the app ever asked it to.
- If you were already connected it says so rather than pretending something happened.
- Their address can be typed instead of scanned, for a phone whose camera you would rather not turn on and for reading one out across a table.
- The camera is only ever asked for at the moment you point it at a card, and nothing it sees is kept.
- The People screen's empty state now says how to fill it.

---

## v0.16.0

2026-07-28

**Web**

- The constellation on the landing page still forms on a very wide screen. Haven caps how many stars it draws, so past about 2560 pixels the lens had fewer and fewer of them to join and the figure thinned to a line or two; it now reaches further out to find a constellation instead.
- A long handle on a public card no longer pushes the platform name off its row. It truncates, which is what it was always meant to do.
- A photo that will not load leaves an ordinary card behind rather than a broken-image icon, which was the first thing a stranger could have seen after scanning somebody's code.

---

## v0.15.0

2026-07-28

**iOS**

- A question you skipped during onboarding stays skipped. It used to be remembered only on the phone you skipped it on, so reinstalling Haven, or signing in on a second phone, asked you everything again.
- Onboarding also stops restarting itself. Clearing your city on My Card used to drop you back into the questions on the next launch, because an empty field and a question nobody had asked looked identical from the app's side.
- Connecting X or LinkedIn now brings your photo across. The picture the provider already has of you lands on your card and lights its star, so the photo question answers itself. A photo you chose yourself is never replaced.

---

## v0.14.0

2026-07-28

**iOS**

- Your card now shows the address it points at, under Your address, and you can change it. Until now Haven picked one for you when you signed up and there was no way to see it, let alone pick a different one.
- If the address you want is taken, Haven says so and offers ones that are free right now, built from your own name. It does not guess for you.
- The editor says what changing it costs before you change it: the code on the back of your card opens that page, and the old address stops working.

---

## v0.13.0

2026-07-28

**iOS**

- Search results open the person. Tapping a name in the results, whether you got there by typing or by pinning a company, city or role chip, now opens their screen with their handles and your note. Until now a result was a dead line of text.
- So do the people an ask names, direct matches and bridges alike.
- Coming back leaves your search exactly as it was: the same words, the same chips, the same answer still on screen.

---

## v0.12.0

2026-07-28

**iOS**

- A person's screen finally shows how to reach them. Their handles are listed with the one you marked primary first, and tapping any of them opens that app: Instagram, X, LinkedIn and Telegram open the profile, a phone number starts a call, a WhatsApp number opens the chat. Haven was already being sent all of this and was throwing it away.
- Their photo is on the screen too, next to their name.
- You can change any of it. An Edit button opens their details: name, photo, city, company, role, and every way to reach them, each edited on its own the way your own card already worked.
- You can delete somebody. It is behind a confirmation that says what goes with them, because what you wrote about them is the part nobody else has a copy of.
- A page a capture recorded for them is shown only when it is not already one of their handles, so one way to reach somebody is never listed twice.

---

## v0.11.0

2026-07-28

**iOS**

- You can add someone by hand. The Add someone button on People has been sitting there disabled since the screen was built; it now opens a sheet asking their name, one way to reach them, and one line about them, and saves them to your directory.
- The handle can be on any of six platforms, not just the three Haven reads shares from: Instagram, X, LinkedIn, phone, WhatsApp and Telegram. Paste a profile link or type the handle; Haven shows you what it will actually store before you save.
- Adding someone works with no signal. The save is written to your phone and sent when there is a connection, the same way a profile shared into Haven is, so nobody is ever lost to a basement.
- If the handle you type is already on somebody in your directory, Haven says who before you save, and your note is added to them rather than filing a second copy of the same person. If the name matches somebody instead, it offers them and lets you decide.

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
