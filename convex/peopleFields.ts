// Plain validators, not registered Convex functions -- schema.ts and
// people.ts both need this exact shape, same reasoning as profileFields.ts.

import { Infer, v } from "convex/values";

// Where a handle's value came from, so a value an OAuth round trip proved is
// never treated the same way as a slug somebody guessed off a screenshot.
// "proven" is Composio's connected-profile handles (composio.ts); "typed" is
// a hand-entered form (addPerson/editPerson default to this when the caller
// sends nothing); "imported" is the OCR/screenshot capture pipeline;
// "guessed" is reserved, unused today, for the LinkedIn slug-guess flow
// (reach.ts's LinkedIn staleness hint reads addedAt, not source -- guessing
// a fresher slug for a stale one is the follow-up that would actually write
// this) -- not dead, just not built yet.
export const handleSourceValidator = v.union(
  v.literal("proven"),
  v.literal("typed"),
  v.literal("imported"),
  v.literal("guessed"),
);
export type HandleSource = Infer<typeof handleSourceValidator>;

// A way to reach a saved person. platform is free-form on purpose: your own
// card offers exactly four platforms, but a person you save manually can
// carry any handle you want to record, WhatsApp and Telegram included
// (mvp-design). Stored trimmed and lowercase so one-per-platform uniqueness
// and the preferredPlatform pointer match by plain equality.
//
// source, platformId and addedAt are all optional and unbackfilled: a row
// written before this field existed simply lacks it, same as every other
// provenance field in this codebase (people.platform, personHandles before
// the index existed). platformId is a platform's own stable numeric/opaque
// id for the account, proven the same way source: "proven" is (composio.ts)
// -- unlike value, which is a username and can be renamed, platformId is
// what actually identifies the account across a rename.
export const contactHandleValidator = v.object({
  platform: v.string(),
  value: v.string(),
  source: v.optional(handleSourceValidator),
  platformId: v.optional(v.string()),
  addedAt: v.optional(v.number()),
});
