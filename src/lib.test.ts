import { describe, expect, test } from "vitest";
import {
  bootMode,
  buildEmbedText,
  CAPTURE_QUEUE_CAP,
  composeAtlasField,
  canSaveManualName,
  composeHeadline,
  composeName,
  decideSwipe,
  deriveProfileUrl,
  formatMonthYear,
  isAdminEmail,
  isClerkFlowHash,
  isJoinHash,
  isValidEmail,
  DEFAULT_ADMIN_EMAILS,
  normalizeEmail,
  parseAdminEmails,
  normalizeUrl,
  resolveView,
  triageCountLabel,
} from "./lib";

describe("resolveView", () => {
  const base = {
    isAuthenticated: false,
    isLoading: false,
    hash: "",
    hasSessionHint: false,
  };

  test("a signed-in visitor always gets home, whatever the hash", () => {
    expect(resolveView({ ...base, isAuthenticated: true })).toBe("home");
    expect(
      resolveView({ ...base, isAuthenticated: true, hash: "#/join" }),
    ).toBe("home");
  });

  test("the signed-out default landing is the waitlist", () => {
    expect(resolveView(base)).toBe("waitlist");
    // A first-time visitor paints the waitlist immediately, before Clerk loads.
    expect(resolveView({ ...base, isLoading: true })).toBe("waitlist");
    expect(resolveView({ ...base, hash: "#/join" })).toBe("waitlist");
  });

  test("Clerk callbacks and the explicit sign-in route mount sign-in", () => {
    expect(resolveView({ ...base, hash: "#/sso-callback" })).toBe("signin");
    expect(resolveView({ ...base, hash: "#/sign-in" })).toBe("signin");
    // A flow hash outranks a returning-visitor splash.
    expect(
      resolveView({
        ...base,
        hash: "#/verify",
        isLoading: true,
        hasSessionHint: true,
      }),
    ).toBe("signin");
  });

  test("a returning visitor waits on the splash while auth resolves", () => {
    expect(
      resolveView({ ...base, isLoading: true, hasSessionHint: true }),
    ).toBe("splash");
    // Once resolved signed-out, they fall through to the waitlist.
    expect(resolveView({ ...base, hasSessionHint: true })).toBe("waitlist");
  });

  test("the waitlist route is never treated as a Clerk flow", () => {
    // #/join matches the generic Clerk-flow shape but must stay public.
    expect(resolveView({ ...base, hash: "#/join" })).toBe("waitlist");
  });
});

describe("normalizeEmail", () => {
  test("trims and lowercases so dedupe is case- and space-insensitive", () => {
    expect(normalizeEmail("  Tony@Example.COM ")).toBe("tony@example.com");
  });
});

describe("parseAdminEmails", () => {
  test("returns the baked-in default when env is unset", () => {
    expect(parseAdminEmails(undefined)).toEqual(
      DEFAULT_ADMIN_EMAILS.map(normalizeEmail),
    );
  });

  test("adds env addresses, normalized, deduped against the default", () => {
    const parsed = parseAdminEmails(
      " Second@Example.com , tonythiennguyen17@gmail.com ",
    );
    expect(parsed).toContain("second@example.com");
    // The default is not duplicated even though env repeats it.
    expect(
      parsed.filter((e) => e === "tonythiennguyen17@gmail.com"),
    ).toHaveLength(1);
  });

  test("ignores empty entries from stray commas", () => {
    expect(parseAdminEmails(",, ,")).toEqual(
      DEFAULT_ADMIN_EMAILS.map(normalizeEmail),
    );
  });
});

describe("isAdminEmail", () => {
  const admins = parseAdminEmails(undefined);

  test("matches an allowlisted address case-insensitively", () => {
    expect(isAdminEmail("TonyThienNguyen17@Gmail.com ", admins)).toBe(true);
  });

  test("rejects a non-admin address", () => {
    expect(isAdminEmail("someone@else.com", admins)).toBe(false);
  });

  test("a missing email is never an admin", () => {
    expect(isAdminEmail(null, admins)).toBe(false);
    expect(isAdminEmail(undefined, admins)).toBe(false);
  });
});

describe("isValidEmail", () => {
  test("accepts an ordinary address", () => {
    expect(isValidEmail("tony@example.com")).toBe(true);
    expect(isValidEmail("a.b+tag@sub.domain.io")).toBe(true);
  });

  test("rejects missing parts, spaces, and empties", () => {
    expect(isValidEmail("")).toBe(false);
    expect(isValidEmail("tony")).toBe(false);
    expect(isValidEmail("tony@")).toBe(false);
    expect(isValidEmail("@example.com")).toBe(false);
    expect(isValidEmail("tony@example")).toBe(false);
    expect(isValidEmail("tony @example.com")).toBe(false);
  });

  test("rejects an address longer than the 254-char limit", () => {
    const long = `${"a".repeat(250)}@ex.com`;
    expect(isValidEmail(long)).toBe(false);
  });
});

describe("isJoinHash", () => {
  test("matches the waitlist route with or without a trailing slash", () => {
    expect(isJoinHash("#/join")).toBe(true);
    expect(isJoinHash("#/join/")).toBe(true);
  });

  test("does not match the app or Clerk flow hashes", () => {
    expect(isJoinHash("")).toBe(false);
    expect(isJoinHash("#/")).toBe(false);
    expect(isJoinHash("#/sso-callback")).toBe(false);
    expect(isJoinHash("#/joinery")).toBe(false);
  });
});

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

  test("encodes a mangled handle so it cannot escape the intended path", () => {
    // A space would otherwise break the URL; a slash would otherwise add a
    // path segment. Both must land as encoded bytes, not raw characters.
    expect(deriveProfileUrl("x", "ada l")).toBe("https://x.com/ada%20l");
    expect(deriveProfileUrl("github", "a/b")).toBe("https://github.com/a%2Fb");
    // Non-ASCII handles must survive as encoded UTF-8 bytes too.
    expect(deriveProfileUrl("x", "caf\u00e9")).toBe("https://x.com/caf%C3%A9");
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

describe("bootMode", () => {
  test("a Clerk flow callback mounts the flow, outranking any session hint", () => {
    // A returning user can still land on "#/sso-callback" (e.g. re-auth); the
    // callback must be honored, not short-circuited into a splash.
    expect(bootMode({ hash: "#/sso-callback", hasSessionHint: false })).toBe(
      "clerk-flow",
    );
    expect(bootMode({ hash: "#/sso-callback", hasSessionHint: true })).toBe(
      "clerk-flow",
    );
    expect(bootMode({ hash: "#/verify", hasSessionHint: true })).toBe(
      "clerk-flow",
    );
  });

  test("a returning visitor (session hint, no flow) splashes until Clerk resolves", () => {
    expect(bootMode({ hash: "", hasSessionHint: true })).toBe("splash");
    expect(bootMode({ hash: "#", hasSessionHint: true })).toBe("splash");
    expect(bootMode({ hash: "#/", hasSessionHint: true })).toBe("splash");
  });

  test("a first-time visitor (no hint, no flow) lands immediately", () => {
    expect(bootMode({ hash: "", hasSessionHint: false })).toBe("landing");
    expect(bootMode({ hash: "#", hasSessionHint: false })).toBe("landing");
    expect(bootMode({ hash: "#/", hasSessionHint: false })).toBe("landing");
  });
});

describe("decideSwipe", () => {
  test("a hard left drag past the threshold commits to save", () => {
    expect(decideSwipe(-300, [{ t: 0, x: -300 }])).toBe("save");
  });

  test("a hard right drag past the threshold commits to context", () => {
    expect(decideSwipe(300, [{ t: 0, x: 300 }])).toBe("context");
  });

  test("a leftward flick under the positional threshold still commits via momentum", () => {
    // Only -50px of drag (threshold is -240), but a fast enough flick left
    // projects well past it -- the card should still save, not settle.
    const samples = [
      { t: 0, x: 0 },
      { t: 50, x: -50 },
    ];
    expect(decideSwipe(-50, samples)).toBe("save");
  });

  test("a small, slow drag settles back", () => {
    expect(decideSwipe(50, [{ t: 0, x: 50 }])).toBe("settle");
  });

  test("settles exactly at the threshold boundary (strictly greater/less to commit)", () => {
    expect(decideSwipe(-240, [{ t: 0, x: -240 }])).toBe("settle");
    expect(decideSwipe(240, [{ t: 0, x: 240 }])).toBe("settle");
  });
});

describe("triageCountLabel", () => {
  test("singular for exactly one", () => {
    expect(triageCountLabel(1)).toBe("1 to review");
  });

  test("plain count below the cap", () => {
    expect(triageCountLabel(0)).toBe("0 to review");
    expect(triageCountLabel(7)).toBe("7 to review");
    expect(triageCountLabel(CAPTURE_QUEUE_CAP - 1)).toBe(
      `${CAPTURE_QUEUE_CAP - 1} to review`,
    );
  });

  test("reads as a floor, not a false exact total, once the queue hits the cap", () => {
    // listCaptures caps its query at CAPTURE_QUEUE_CAP; at that count the
    // client cannot tell whether more are queued server-side.
    expect(triageCountLabel(CAPTURE_QUEUE_CAP)).toBe(
      `${CAPTURE_QUEUE_CAP}+ to review`,
    );
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
