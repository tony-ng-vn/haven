// Plain helper, not a registered Convex function -- profiles.ts, people.ts,
// and captures.ts all validate an uploaded image the same way, and one
// definition keeps the rule from drifting.
//
// Never trust the client's claim about what it uploaded: read the metadata
// Convex recorded for the blob before accepting it. A rejected upload's blob
// is deliberately NOT deleted here: a mutation that throws rolls back every
// effect, storage deletes included, so cleanup of stray uploads belongs to
// sweepOrphanedUploads in captures.ts.

import { MutationCtx } from "./_generated/server";
import { Id } from "./_generated/dataModel";

export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

export async function requireImageBlob(
  ctx: MutationCtx,
  storageId: Id<"_storage">,
  message: string,
): Promise<void> {
  const meta = await ctx.db.system.get("_storage", storageId);
  const isValidImage =
    meta !== null &&
    meta.contentType !== undefined &&
    meta.contentType.startsWith("image/") &&
    meta.size <= MAX_IMAGE_BYTES;
  if (!isValidImage) {
    throw new Error(message);
  }
}
