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

export default crons;
