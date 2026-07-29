# App Store metadata, first draft

Everything App Store Connect asks for as text, drafted here so it can be argued
with in a diff rather than typed into a web form at midnight.
Unit H1 of `superpowers/plans/2026-07-28-frontend-completion-plan.md`.

Nothing here is submitted by a commit.
Every field below is copied into App Store Connect by hand, and the screenshots
are captured on a Mac.
Treat this as the draft, not the record: once it is in App Store Connect, that
is the record.

## The name

**Haven** is crowded on the App Store and the name is not reserved yet, which is
the longest-lead item on the whole list and has been open since Phase 6 was
written.
Reserve it before anything else here matters.

If it is taken, the fallbacks worth checking in order, because each keeps the
address and the word: **Haven: Your People**, **Haven Contacts**, **inHaven**.
The last one matches the domain and is the only one that survives somebody
searching for the app by the address on a card.

## Subtitle

Thirty characters, App Store Connect's limit.

> Remember the people you meet

Twenty-eight. Says the job, uses no jargon, and does not promise a network.

Rejected: "Your network, remembered" (sells a network before there is one),
"Contacts with memory" (reads as a system-app replacement, which it is not).

## Description

Under 4000 characters. This is roughly 1100.

> You meet someone worth remembering. A week later you have their handle and
> nothing else -- not where you met, not what they were working on, not why you
> wanted to stay in touch.
>
> Haven is for that.
>
> **Save them in seconds.** Share a profile from Instagram, LinkedIn or X
> straight into Haven, or write somebody down by hand. Either way you get asked
> one thing while you still remember it: how you met, what you talked about.
> That one line is the whole product.
>
> **It works with no signal.** A person saved in a basement is saved. Haven
> writes to your phone first and sends it when there is a connection, so
> capture never fails at the moment it matters.
>
> **Find them by what you remember.** Search everyone you know by a word from
> your own note, or narrow by company, city or role. When you cannot remember
> the word, ask: "who did I meet who works on databases?" Haven reads your
> whole network and answers in your own words, quoting the note that made each
> person a match -- and when nobody fits directly, it tells you who could
> introduce you, and why.
>
> **Reach them in one tap.** Their handles open the app they are actually in.
> A phone number dials.
>
> **Connect in person.** Show the back of your card, they scan it, and you are
> both in each other's directories -- with a card that stays current. Change
> your job and everyone connected to you sees it.
>
> Your card is a constellation, drawn from your name, and it is yours. Nothing
> in Haven posts anywhere. Nothing follows you across other apps.

## Keywords

One hundred characters, comma separated, no spaces after commas, and never
repeat a word already in the name or subtitle.

> contacts,networking,crm,memory,notes,people,conference,event,follow up,
> business card,qr,connect

Ninety-eight characters. Deliberately excludes "haven", "remember" and "meet",
which are already in the name and subtitle and would be wasted.

## Category

**Primary: Productivity.** **Secondary: Business.**

Not Social Networking, which is where the algorithm would put a contacts app
with a QR code, and which sets an expectation of a feed Haven does not have.

## Age rating

**4+.** No user-generated content shown to anybody else, no web browsing beyond
the privacy and terms pages, no ads, no gambling, no purchases.

The one question worth answering carefully on the questionnaire: Haven shows
content another person wrote *only* to somebody already connected to them, and
only their own card fields. That is not user-generated content in the sense the
form means.

## URLs

- **Support URL**: `https://inhavens.com/support` -- a real page now, public and
  signed out.
  It answers sign-in trouble, account deletion (in the app and by mail), whether
  notes are visible to the people they are about, and how to reach a person.
- **Marketing URL**: `https://inhavens.com`
- **Privacy Policy URL**: `https://inhavens.com/privacy` -- live, and reachable
  from inside the app, which Review rule 5.1.1(i) asks for.

## Screenshots

Required at 6.9" (iPhone 17 Pro Max or equivalent). Five, in this order, because
the order is the argument.

1. **The card.** The reveal at the end of onboarding, constellation complete.
   It is the thing people screenshot on their own.
2. **A person's screen**, with a note written and handles visible. Money screen
   two, and the one that says what the app is for.
3. **The ask panel**, answered, with a bridge match showing its reasoning. The
   feature nothing else does.
4. **Search**, with a chip pinned and results. Proves it is a real directory.
5. **The card back**, code up, with the address underneath.

Capture on a simulator with a signed build and a seeded account, not on a real
directory: every name on a screenshot is a real person otherwise.

**Use obviously-invented people.** The previews in the repo already use them
(Maya Chen, Ada Lovelace, Mai Tran) and the same names are safe here.

## Export compliance

Answered in `ios/Haven/Info.plist` rather than on every upload:
`ITSAppUsesNonExemptEncryption` is `false`.

That is truthful rather than a shortcut -- the only encryption Haven uses is
HTTPS to Convex and Clerk, plus the SHA256 nonce Sign in with Apple requires,
and both are exempt under category 5 part 2.
Revisit the day Haven ships its own cryptography, which connect tokens or
end-to-end shared notes would both mean.

## App Privacy answers

Must match `ios/Haven/PrivacyInfo.xcprivacy` and the policy at
`inhavens.com/privacy`; all three are one answer given three times, and Review
checks the first two against each other.

- **Data used to track you**: none.
- **Data linked to you**: name, contact info, photos, user content, identifiers.
  All of it, because Haven is an account -- your card and your directory are the
  product, and none of it is anonymous.
- **Data not linked to you**: none.
- **Purpose** for every type: App Functionality. Nothing is used for analytics,
  advertising, or personalisation.

Note for the reviewer if one is asked for: the camera is used only to read a QR
code, no frame is stored or uploaded, and that is why it appears in neither
list.

## What is still open

- The name is not reserved. Everything else here is moot until it is.
- ~~There is no support page.~~ Built: `inhavens.com/support`.
  The one open question on it is whether to promise a reply time. The page
  currently promises none, because that is the user's commitment to make and not
  the agent's to invent.
- Screenshots need a Mac, a signed build, and a seeded account.
- `MARKETING_VERSION` is still `0.1.0` and moves when the submission build is
  cut, not before.
