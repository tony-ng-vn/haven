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
// OAuth round trip happened: X hands back the username, so it is verified,
// while LinkedIn only proves the person and leaves the slug hand-confirmed.
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
