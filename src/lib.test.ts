import { describe, expect, test } from "vitest";
import {
  buildEmbedText,
  composeAtlasField,
  canSaveManualName,
  composeHeadline,
  composeName,
  deriveProfileUrl,
  formatMonthYear,
  isClerkFlowHash,
  normalizeUrl,
} from "./lib";

describe("normalizeUrl", () => {
  test("keeps http and https URLs as they are", () => {
    expect(normalizeUrl("https://example.com/a")).toBe("https://example.com/a");
    expect(normalizeUrl("http://example.com")).toBe("http://example.com");
  });

  test("adds https to bare domains people actually type", () => {
    expect(normalizeUrl("linkedin.com/in/tony")).toBe(
      "https://linkedin.com/in/tony",
    );
  });

  test("trims surrounding whitespace", () => {
    expect(normalizeUrl("  https://a.com  ")).toBe("https://a.com");
  });

  test("rejects text that is not a link", () => {
    expect(normalizeUrl("met at the conference")).toBe(null);
    expect(normalizeUrl("")).toBe(null);
    expect(normalizeUrl("   ")).toBe(null);
    expect(normalizeUrl("ftp://example.com")).toBe(null);
  });
});

describe("formatMonthYear", () => {
  test("formats a mid-month timestamp as month and year", () => {
    // Mid-month so no timezone offset can shift the month.
    const ms = Date.UTC(2026, 5, 15);
    expect(formatMonthYear(ms, "en-US")).toBe("June 2026");
  });
});

describe("deriveProfileUrl", () => {
  test("derives handle-based platform URLs, stripping a leading @", () => {
    expect(deriveProfileUrl("x", "@ada_l")).toBe("https://x.com/ada_l");
    expect(deriveProfileUrl("instagram", "grace.h")).toBe(
      "https://instagram.com/grace.h",
    );
    expect(deriveProfileUrl("github", "@torvalds")).toBe(
      "https://github.com/torvalds",
    );
  });

  test("keeps the @ where the platform URL requires it", () => {
    expect(deriveProfileUrl("tiktok", "ada")).toBe(
      "https://www.tiktok.com/@ada",
    );
    expect(deriveProfileUrl("threads", "@ada")).toBe(
      "https://www.threads.net/@ada",
    );
  });

  test("bluesky handles are domain-like paths", () => {
    expect(deriveProfileUrl("bluesky", "ada.bsky.social")).toBe(
      "https://bsky.app/profile/ada.bsky.social",
    );
  });

  test("slug-based and unknown platforms cannot be derived", () => {
    expect(deriveProfileUrl("linkedin", "ada-lovelace")).toBe(null);
    expect(deriveProfileUrl("facebook", "ada")).toBe(null);
    expect(deriveProfileUrl("other", "ada")).toBe(null);
  });

  test("missing or blank handles derive nothing", () => {
    expect(deriveProfileUrl("x", undefined)).toBe(null);
    expect(deriveProfileUrl("x", "   ")).toBe(null);
    expect(deriveProfileUrl("x", "@")).toBe(null);
  });
});

describe("buildEmbedText", () => {
  test("assembles all fields deterministically, one per line", () => {
    expect(
      buildEmbedText({
        name: "Ada Lovelace",
        platform: "x",
        handle: "@ada_l",
        headline: "Compiler engineer",
        context: "Met at the analytical engines meetup.",
      }),
    ).toBe(
      "Ada Lovelace\nx @ada_l\nCompiler engineer\nMet at the analytical engines meetup.",
    );
  });

  test("skips missing and blank parts", () => {
    expect(buildEmbedText({ name: "Grace Hopper" })).toBe("Grace Hopper");
    expect(
      buildEmbedText({ name: "Grace Hopper", headline: "  ", context: "Navy." }),
    ).toBe("Grace Hopper\nNavy.");
  });

  test("platform line renders with either part alone", () => {
    expect(buildEmbedText({ name: "A", handle: "@a" })).toBe("A\n@a");
    expect(buildEmbedText({ name: "A", platform: "github" })).toBe(
      "A\ngithub",
    );
  });
});

describe("composeName", () => {
  test("joins first and last with a single space", () => {
    expect(composeName("Ada", "Lovelace")).toBe("Ada Lovelace");
  });

  test("trims each part and collapses runs of inner whitespace", () => {
    expect(composeName("  Mary   Jane ", "Watson")).toBe("Mary Jane Watson");
  });

  test("returns just the part that was typed when the other is blank", () => {
    expect(composeName("Ada", "")).toBe("Ada");
    expect(composeName("", "Lovelace")).toBe("Lovelace");
    expect(composeName("  ", "Grace")).toBe("Grace");
  });

  test("returns empty string when both parts are empty or whitespace", () => {
    expect(composeName("", "")).toBe("");
    expect(composeName("   ", "  ")).toBe("");
  });
});

describe("composeHeadline", () => {
  test("joins work and school with a double-hyphen separator", () => {
    expect(composeHeadline("Convex", "MIT")).toBe("Convex -- MIT");
  });

  test("returns the single part when only one is given", () => {
    expect(composeHeadline("Convex", "")).toBe("Convex");
    expect(composeHeadline("  ", "MIT")).toBe("MIT");
  });

  test("trims each part before combining", () => {
    expect(composeHeadline("  Convex  ", "  MIT  ")).toBe("Convex -- MIT");
  });

  test("returns undefined when neither is given", () => {
    expect(composeHeadline("", "")).toBeUndefined();
    expect(composeHeadline("   ", "  ")).toBeUndefined();
  });
});

describe("canSaveManualName", () => {
  test("false until the composed name has real characters", () => {
    expect(canSaveManualName("")).toBe(false);
    expect(canSaveManualName("   ")).toBe(false);
  });

  test("true once someone is actually named", () => {
    expect(canSaveManualName("Ada Lovelace")).toBe(true);
  });
});

describe("isClerkFlowHash", () => {
  test("true for Clerk OAuth/verification callback routes", () => {
    expect(isClerkFlowHash("#/sso-callback")).toBe(true);
    expect(isClerkFlowHash("#/verify")).toBe(true);
    expect(isClerkFlowHash("#/factor-one")).toBe(true);
  });

  test("false for the bare landing (no hash route)", () => {
    expect(isClerkFlowHash("")).toBe(false);
    expect(isClerkFlowHash("#")).toBe(false);
    expect(isClerkFlowHash("#/")).toBe(false);
  });
});

describe("composeAtlasField", () => {
  const p = (id: string) => ({ _id: id, name: id });

  test("keeps the recent field unchanged when matches are already in it", () => {
    const recent = [p("a"), p("b"), p("c")];
    const out = composeAtlasField(recent, [p("b")], [p("c")]);
    expect(out.map((x) => x._id)).toEqual(["a", "b", "c"]);
  });

  test("materializes off-field name matches after the recent field", () => {
    const recent = [p("a"), p("b")];
    const out = composeAtlasField(recent, [p("z"), p("a")], []);
    // Recent people keep their spiral indices; the off-field match appends.
    expect(out.map((x) => x._id)).toEqual(["a", "b", "z"]);
  });

  test("appends semantic-only matches last and dedupes across groups", () => {
    const recent = [p("a")];
    const out = composeAtlasField(recent, [p("z")], [p("z"), p("m"), p("a")]);
    expect(out.map((x) => x._id)).toEqual(["a", "z", "m"]);
  });
});
