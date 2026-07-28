# Changelog

What changed in Haven, newest first, written for someone using the product
rather than reading the diff.

Entries begin at v0.2.0. Everything before that lives in the git log and the
pull requests, which is where it is easiest to read anyway.

## v0.2.0

2026-07-28

**Backend**

- Haven can now tell whether a signed-in person is a paying subscriber, and that answer comes from Stripe rather than from anything the app or a browser claims. Subscriptions that start, change, lapse, or get cancelled in Stripe are picked up on their own. Nothing is charged yet, and there is no checkout screen: this is the groundwork one will sit on.

---
