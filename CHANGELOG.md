# Changelog

What changed in Haven, newest first, written for someone using the product
rather than reading the diff.

Entries begin at v0.2.0. Everything before that lives in the git log and the
pull requests, which is where it is easiest to read anyway.

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
