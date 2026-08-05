// Plain validators, not registered Convex functions -- schema.ts and
// profiles.ts both need this exact shape, and one definition is what keeps
// the stored document and the mutation arguments from drifting apart.

import { v } from "convex/values";

// Email is deliberately absent: it was cut from the contact step on
// 2026-07-24 and nothing should reintroduce it as a platform.
export const platformValidator = v.union(
  v.literal("instagram"),
  v.literal("x"),
  v.literal("linkedin"),
  v.literal("phone"),
);

// `verified` means the handle VALUE itself was proven, not merely that an
// OAuth round trip happened. Composio's connected profile tools prove this
// for LinkedIn, Instagram and X (see composio.ts); a typed-in handle is the
// only kind that is ever stored unverified.
export const handleValidator = v.object({
  platform: platformValidator,
  value: v.string(),
  verified: v.boolean(),
});

// The platforms whose handle is safe to render on the public web card.
// Phone is absent by construction, so getByHandle's return validator makes a
// leaked phone number structurally impossible rather than merely unlikely.
export const publicHandleValidator = v.object({
  platform: v.union(
    v.literal("instagram"),
    v.literal("x"),
    v.literal("linkedin"),
  ),
  value: v.string(),
  verified: v.boolean(),
});

// The three onboarding questions, in the order they are asked.
export const onboardingStepValidator = v.union(
  v.literal("name"),
  v.literal("location"),
  v.literal("contact"),
);

// What happened to one question. "asked and declined" is a fact the card
// itself cannot carry: a skipped city and a city nobody got round to asking
// for leave the same empty field, which is exactly why this record exists
// rather than the client inferring progress from the card.
export const onboardingStateValidator = v.union(
  v.literal("answered"),
  v.literal("skipped"),
);

// Progress through onboarding, per question. Every member is optional: a
// question nobody has reached yet is absent rather than pending, so a row
// written before this field existed is already valid.
export const onboardingValidator = v.object({
  name: v.optional(onboardingStateValidator),
  location: v.optional(onboardingStateValidator),
  contact: v.optional(onboardingStateValidator),
  // Stamped once every question has been decided, however it was decided.
  // Reaching the end by skipping is still reaching the end.
  completedAt: v.optional(v.number()),
});

// What the client sends: admin (state or region) and country are optional
// because the city picker accepts a raw typed city when the completer
// returns nothing.
export const cityInputValidator = v.object({
  name: v.string(),
  admin: v.optional(v.string()),
  country: v.optional(v.string()),
});

// What we store: the same city plus the accent-insensitive lowercase key
// Phase 3 filters on (see normalizeName in nameSearch.ts).
export const cityValidator = v.object({
  name: v.string(),
  admin: v.optional(v.string()),
  country: v.optional(v.string()),
  normalized: v.string(),
});

// A profile's city carries the accent-folded `normalized` key; a person's
// does not, and Convex object validators reject unknown fields. Anything
// copying one onto the other has to drop it here rather than spread the
// whole object -- which fails at runtime, not at compile time, because
// structural typing is happy to pass the wider shape.
export function toCityInput(
  city: { name: string; admin?: string; country?: string } | undefined,
): { name: string; admin?: string; country?: string } | undefined {
  if (city === undefined) {
    return undefined;
  }
  return { name: city.name, admin: city.admin, country: city.country };
}
