# Changelog

What changed in Haven, newest first, written for someone using the product
rather than reading the diff.

Entries begin at v0.2.0. Everything before that lives in the git log and the
pull requests, which is where it is easiest to read anyway.

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
