import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

// What ios/project.yml claims Haven runs on.
//
// These two settings are the ones nobody sets and everybody inherits: leave
// them out and Xcode's defaults apply, which are iPhone *and* iPad in every
// orientation. That is not a neutral default -- Apple reviews an app on every
// device and orientation it claims, so an unset value is a promise made by
// omission. Haven has no size-class handling anywhere in ios/Haven and no
// screen designed sideways, so both claims were false until they were written
// down.
//
// Tested from here rather than in Swift because a test that reads project
// source at runtime is fragile on a simulator, and because this way the guard
// runs on the Linux runner in a second instead of waiting for a Mac.

const projectYml = readFileSync("ios/project.yml", "utf8");

/// The value of a build setting in the top-level `settings.base` block.
function baseSetting(key: string): string | null {
  // Non-greedy up to the first `targets:` so a per-target override of the same
  // key cannot be mistaken for the project-wide one.
  const base = projectYml.split(/^targets:/m)[0];
  const match = base.match(new RegExp(`^\\s*${key}:\\s*(.+?)\\s*$`, "m"));
  if (match === null) return null;
  return match[1].replace(/^["']|["']$/g, "");
}

describe("what ios/project.yml claims Haven runs on", () => {
  // "1" is iPhone. "2" is iPad, and "1,2" is both, which is Xcode's default
  // and was what shipped until somebody looked.
  test("claims iPhone only", () => {
    expect(baseSetting("TARGETED_DEVICE_FAMILY")).toBe("1");
  });

  // Absent means every orientation, including landscape on iPhone -- the
  // primary target, where no screen has been designed sideways either.
  test("claims portrait only", () => {
    expect(baseSetting("INFOPLIST_KEY_UISupportedInterfaceOrientations")).toBe(
      "UIInterfaceOrientationPortrait",
    );
  });

  // If this ever fails, the fix is not to loosen it. It is to open Haven on an
  // iPad, look at every screen, and add the size-class handling that does not
  // exist yet -- then change this test in the same commit.
  test("makes no claim it cannot back", () => {
    // Unset is the dangerous case, not a safe one: Xcode fills it in as "1,2".
    // Reading a missing value as "claims nothing" would have let this test pass
    // on exactly the configuration it exists to catch.
    const family = baseSetting("TARGETED_DEVICE_FAMILY") ?? "1,2";
    const claimsIpad = family.split(",").includes("2");
    const hasSizeClassHandling = /horizontalSizeClass|userInterfaceIdiom/.test(
      readFileSync("ios/Haven/RootView.swift", "utf8"),
    );
    expect(claimsIpad && !hasSizeClassHandling).toBe(false);
  });
});
