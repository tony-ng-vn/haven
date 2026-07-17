import { describe, expect, test } from "vitest";
import {
  buildEmbedText,
  deriveProfileUrl,
  formatMonthYear,
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
