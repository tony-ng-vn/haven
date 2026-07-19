import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

// Self-heals people whose embed action failed (or a scheduled retry got
// lost) without needing a human to notice and run the backfill by hand.
const crons = cronJobs();

crons.interval(
  "embed backfill",
  { hours: 24 },
  internal.people.backfillEmbeddings,
  {},
);

// Self-heals a capture stuck "pending" because the extract action was
// killed rather than throwing (timeout, redeploy) -- see sweepStuckCaptures.
crons.interval(
  "sweep stuck captures",
  { minutes: 30 },
  internal.captures.sweepStuckCaptures,
  {},
);

// Deletes screenshot blobs an abandoned upload left with no capture or
// person ever pointing to them -- see sweepOrphanedUploads.
crons.interval(
  "sweep orphaned uploads",
  { hours: 24 },
  internal.captures.sweepOrphanedUploads,
  {},
);

export default crons;
