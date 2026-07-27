import { defineConfig, configDefaults } from "vitest/config";

// Nested dev worktrees under .worktrees/ carry their own copies of these
// test files; without this the suite runs every copy (slow) and surfaces
// failures from stale branches we never touched.
const exclude = [...configDefaults.exclude, "**/.worktrees/**"];

export default defineConfig({
  test: {
    environment: "edge-runtime",
    server: { deps: { inline: ["convex-test"] } },
    exclude,
    // convex/people.test.ts exercises a convex-test scheduler race (a
    // starved retry timer can double-start the embed retry job) that only
    // shows up under CPU contention from other files running at the same
    // time. Splitting it into its own project with a later sequence
    // groupOrder guarantees it runs alone, in a single fork, after every
    // other file's group has finished -- not just "isolated" within a
    // shared worker pool, which would not remove the contention.
    projects: [
      {
        extends: true,
        test: {
          name: "convex",
          exclude: [...exclude, "convex/people.test.ts"],
        },
      },
      {
        extends: true,
        test: {
          name: "convex-people-serial",
          include: ["convex/people.test.ts"],
          exclude,
          pool: "forks",
          poolOptions: { forks: { singleFork: true } },
          sequence: { groupOrder: 1 },
        },
      },
    ],
  },
});
