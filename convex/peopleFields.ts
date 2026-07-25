// Plain validators, not registered Convex functions -- schema.ts and
// people.ts both need this exact shape, same reasoning as profileFields.ts.

import { v } from "convex/values";

// A way to reach a saved person. platform is free-form on purpose: your own
// card offers exactly four platforms, but a person you save manually can
// carry any handle you want to record, WhatsApp and Telegram included
// (mvp-design). Stored trimmed and lowercase so one-per-platform uniqueness
// and the preferredPlatform pointer match by plain equality.
export const contactHandleValidator = v.object({
  platform: v.string(),
  value: v.string(),
});
