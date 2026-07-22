import { defineConfig, configDefaults } from "vitest/config";

export default defineConfig({
  test: {
    environment: "edge-runtime",
    server: { deps: { inline: ["convex-test"] } },
    // Nested dev worktrees under .worktrees/ carry their own copies of these
    // test files; without this the suite runs every copy (slow) and surfaces
    // failures from stale branches we never touched.
    exclude: [...configDefaults.exclude, "**/.worktrees/**"],
  },
});
