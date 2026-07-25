// One voice for the waitlist, on every viewport.
//
// Mode ("desktop" | "phone") only changes layout in CSS. It must never key
// marketing copy -- that is how "Join" on web and "Request access" on phone
// shipped as two different products. Change wording here; the test below
// locks the contract that there is not a second set for narrow screens.

export const WAITLIST_COPY = {
  eyebrow: "Haven - private beta",
  headline: "Your people are a constellation.",
  sub: "Every person you meet becomes a point of light - and Haven keeps them from drifting away.",
  cta: "Join",
  submitting: "Joining",
  fine: "Private beta",
  joinedTitle: "You are on the list.",
  alreadyTitle: "You're already on the list.",
  joinedBody:
    "Thank you for joining us, to be in the true social that brings you to other people in your life",
  alreadyBody:
    "This email is already registered - no need to sign up again. We'll be in touch.",
} as const;
