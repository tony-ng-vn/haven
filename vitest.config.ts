import { defineConfig, configDefaults } from "vitest/config";

// Nested dev worktrees carry their own copies of these test files; without
// this the suite runs every copy (slow) and surfaces failures from stale
// branches we never touched. Tooling plugins create theirs under
// .claude/worktrees/, hence the second glob.
const exclude = [
  ...configDefaults.exclude,
  "**/.worktrees/**",
  "**/.claude/worktrees/**",
];

// The embed-retry files; see the projects comment below for why they cannot
// share a worker pool with anything else.
const serial = ["convex/people.test.ts", "convex/memories.test.ts"];

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
        },
      },
    ],
  },
});
