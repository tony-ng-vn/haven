# Changelog

What changed in Haven, newest first, written for someone using the product
rather than reading the diff.

Entries begin at v0.2.0. Everything before that lives in the git log and the
pull requests, which is where it is easiest to read anyway.

## v0.3.0

2026-07-28

**iOS**

- Your card has a back now. Tap it and it turns over to show the code someone else points a camera at, along with your Haven address underneath in case they cannot scan it. The screen brightens on its own while the code is up, because a dim screen is the most common reason a scan fails.
- The separate beacon screen is gone, and so is the QR button that used to sit in the People toolbar. There is one card and you turn it over, rather than two places showing the same thing. The Lock Screen widget still works and now opens your card already turned to the code.
- The card itself lies flat and drifts gently side to side, with its sky sliding the other way behind it, so it reads as an object held against the night rather than a panel printed on the screen. It has a printed double rule around its edge, and the reveal at the end of onboarding now shows exactly the same card My Card does.

---

## v0.2.0

2026-07-28

**Backend**

- Haven can now tell whether a signed-in person is a paying subscriber, and that answer comes from Stripe rather than from anything the app or a browser claims. Subscriptions that start, change, lapse, or get cancelled in Stripe are picked up on their own. Nothing is charged yet, and there is no checkout screen: this is the groundwork one will sit on.

---
