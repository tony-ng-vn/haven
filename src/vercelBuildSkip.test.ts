import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

// Vercel runs `ignoreCommand` before every build and cancels the build when it
// exits 0, without spending a deployment. That is worth having because most
// pull requests here change `ios/` or `convex/` and cannot affect the web app
// at all: over the 40 merges before this was added, 33 built a bundle that had
// not changed, and preview builds were three quarters of the account's daily
// deployments.
//
// The dangerous half is production. The production build is the only thing
// that runs `npx convex deploy`, so a skipped production build is a backend
// that silently never ships. That is what the first test below exists to
// prevent -- the exit codes are inverted from the intuition (0 skips, non-zero
// builds), which is exactly the kind of thing that gets refactored wrong.

const vercel = JSON.parse(readFileSync("vercel.json", "utf8")) as {
  ignoreCommand?: string;
};

const ignore = vercel.ignoreCommand ?? "";

describe("the ignored build step", () => {
  test("exists", () => {
    expect(ignore).not.toBe("");
  });

  // `exit 1` means "do not skip". Production must reach this branch before any
  // path comparison can run, or a convex-only change stops deploying.
  test("never skips a production build, whatever changed", () => {
    expect(ignore).toMatch(
      /if\s+\[\s+"\$VERCEL_ENV"\s+=\s+production\s+\];\s+then\s+exit\s+1;\s+fi/,
    );
    expect(ignore.indexOf("VERCEL_ENV")).toBeLessThan(ignore.indexOf("git diff"));
  });

  // Compared against the merge base rather than HEAD^: a pull request whose
  // last commit happens to touch only convex/ still has a web diff overall,
  // and reviewers would otherwise be shown a preview one commit stale.
  test("compares the whole branch against main, not just the last commit", () => {
    expect(ignore).toContain("origin/main...HEAD");
  });

  // A failed fetch exits non-zero, which builds. Every failure mode here has
  // to fall towards building: a wasted build costs a deployment, a wrongly
  // skipped one ships nothing and says it succeeded.
  test("builds rather than skips when it cannot tell", () => {
    expect(ignore).toContain("|| exit 1");
  });

  // Everything the web bundle is built from. A path missing here is a change
  // that ships without a preview.
  test("watches every path the web build reads", () => {
    for (const path of [
      "src/",
      "public/",
      "index.html",
      "vite.config.ts",
      "vercel.json",
      "package.json",
      "package-lock.json",
    ]) {
      expect(ignore).toContain(path);
    }
  });
});
