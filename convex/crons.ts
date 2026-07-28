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

// Same self-heal for the per-memory vectors, and how the one-off
// memories:backfillMemories migration gets its rows embedded.
crons.interval(
  "memory embed backfill",
  { hours: 24 },
  internal.memories.backfillMemoryEmbeddings,
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

// Deletes blobs an abandoned upload left with no capture, person, or profile
// ever pointing to them -- see sweepOrphanedUploads. Any new table that stores
// a storage id has to be added to that sweep, or its files get deleted.
crons.interval(
  "sweep orphaned uploads",
  { hours: 24 },
  internal.captures.sweepOrphanedUploads,
  {},
);

// Deletes Love Alarm presence rows past their expiry -- see
// sweepExpiredPresence. Reads already filter them out, so this is about not
// keeping a record of where somebody was for longer than they opted in to.
crons.interval(
  "sweep expired presence",
  { minutes: 30 },
  internal.loveAlarm.sweepExpiredPresence,
  {},
);

export default crons;
