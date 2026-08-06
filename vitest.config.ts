import { defineConfig, configDefaults } from "vitest/config";

// Nested dev worktrees under .worktrees/ carry their own copies of these
// test files; without this the suite runs every copy (slow) and surfaces
// failures from stale branches we never touched.
const exclude = [...configDefaults.exclude, "**/.worktrees/**"];

// The embed-retry files, plus profiles.test.ts, whose fan-out test has the
// same shape (fake timers + finishAllScheduledFunctions over scheduled embed
// jobs) and hits the same race -- it was the suite's top flake in CI and
// locally until it joined this list. See the projects comment below for why
// these cannot share a worker pool with anything else.
const serial = [
  "convex/people.test.ts",
  "convex/memories.test.ts",
  "convex/profiles.test.ts",
];

export default defineConfig({
  test: {
    environment: "edge-runtime",
    server: { deps: { inline: ["convex-test"] } },
    exclude,
    // These files exercise a convex-test scheduler race (a starved retry
    // timer can double-start the embed retry job) that only shows up under
    // CPU contention from other files running at the same time. Splitting
    // them into their own project with a later sequence groupOrder
    // guarantees they run alone, in a single fork, after every other file's
    // group has finished -- not just "isolated" within a shared worker
    // pool, which would not remove the contention.
    projects: [
      {
        extends: true,
        test: {
          name: "convex",
          exclude: [...exclude, ...serial],
        },
      },
      {
        extends: true,
        test: {
          name: "convex-people-serial",
          include: serial,
          exclude,
          pool: "forks",
          poolOptions: { forks: { singleFork: true } },
          sequence: { groupOrder: 1 },
          // Serialization is not enough on its own: the starved-timer race
          // lives in convex-test's scheduler, and on the shared self-hosted
          // Mac (which is also somebody's workday machine) any daytime load
          // can starve it even with the whole pool to itself. Each test
          // builds a fresh convexTest world, so a retry is a clean second
          // roll of the same dice; a real regression still fails every
          // attempt.
          retry: 3,
        },
      },
    ],
  },
});
