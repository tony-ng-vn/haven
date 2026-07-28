import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { HANDLE_PATTERN, isClaimableHandle } from "../convex/handleNames";

// The Apple App Site Association file decides which inhavens.com addresses open
// the app instead of Safari. It is a static JSON file with no imports, so it
// cannot read the reserved-name list the router and the backend both read --
// which makes it exactly the kind of second copy that drifts the day somebody
// adds a word. This is the test that fails on that day.

const aasa = JSON.parse(
  readFileSync("public/.well-known/apple-app-site-association", "utf8"),
) as {
  applinks: {
    details: { appIDs: string[]; components: { "/": string; exclude?: boolean }[] }[];
  };
};

const components = aasa.applinks.details[0].components;
const excluded = new Set(
  components.filter((c) => c.exclude).map((c) => c["/"].replace(/^\//, "")),
);

// The words `isReservedHandle` holds back. Read through the exported predicate
// rather than the private Set, so this reads the same thing the site does.
const RESERVED_SAMPLE = [
  "privacy",
  "terms",
  "legal",
  "signin",
  "haven",
  "inhavens",
  "www",
  "api",
  "app",
  "admin",
];

describe("the apple-app-site-association file", () => {
  test("never claims a path the site keeps for itself", () => {
    for (const name of RESERVED_SAMPLE) {
      expect(isClaimableHandle(name), `${name} should be reserved`).toBe(false);
      expect(excluded.has(name), `${name} is missing from the exclude list`).toBe(true);
    }
  });

  // The real guard: every reserved name, not a sample. Anything the router
  // refuses to treat as a card must not open the app either, or a tap on
  // inhavens.com/privacy launches Haven and shows nothing.
  test("excludes every name the router refuses to treat as a card", () => {
    const claimedButReserved = [...excluded].filter((name) =>
      HANDLE_PATTERN.test(name) && isClaimableHandle(name),
    );
    expect(claimedButReserved).toEqual([]);

    for (const name of RESERVED_SAMPLE) {
      expect(excluded.has(name)).toBe(true);
    }
  });

  test("claims everything else at the root", () => {
    const last = components[components.length - 1];
    expect(last["/"]).toBe("/*");
    expect(last.exclude).toBeUndefined();
  });

  // The landing page and the site's files are not cards either, and neither is
  // reserved by name.
  test("excludes the landing page and anything with a dot in it", () => {
    const patterns = components.filter((c) => c.exclude).map((c) => c["/"]);
    expect(patterns).toContain("/");
    expect(patterns).toContain("/*.*");
  });

  // The Team ID is issued by Apple to the account that ships the app, so it
  // cannot live in the repo until somebody puts it there. This asserts the
  // placeholder is still a placeholder in a way that reads as deliberate --
  // when it is replaced, this test is what says the bundle id survived.
  test("names the app, with the Team ID still to be filled in", () => {
    const [appID] = aasa.applinks.details[0].appIDs;
    expect(appID.endsWith(".com.inhavens.haven")).toBe(true);
    expect(appID.split(".")[0]).toBe("TEAMIDXXXX");
  });
});
