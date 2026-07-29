import { describe, expect, test } from "vitest";
import {
  bootMode,
  buildDossier,
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
  isAuthPath,
  isClerkFlowHash,
  isJoinHash,
  isValidEmail,
  legalDocFromPath,
  sitePageFromPath,
  DEFAULT_ADMIN_EMAILS,
  nameGuessFromSlug,
  normalizeEmail,
  parseAdminEmails,
  normalizeUrl,
  parseProfileUrl,
  handleFromPath,
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

  test("includes the structured card fields when present", () => {
    expect(
      buildEmbedText({
        name: "Ada Lovelace",
        role: "Compiler engineer",
        company: "Analytical Engines",
        cityName: "London",
        context: "Met at the meetup.",
      }),
    ).toBe(
      "Ada Lovelace\nCompiler engineer at Analytical Engines\nLondon\nMet at the meetup.",
    );
    // One side alone still reads as a sentence fragment, not "at undefined".
    expect(buildEmbedText({ name: "Ada", company: "Analytical Engines" })).toBe(
      "Ada\nAnalytical Engines",
    );
    expect(buildEmbedText({ name: "Ada", role: "Engineer" })).toBe(
      "Ada\nEngineer",
    );
  });

  test("the bio joins the haystack after the headline", () => {
    expect(
      buildEmbedText({
        name: "Ada Lovelace",
        headline: "Compiler engineer",
        bio: "Building symbolic math tools.",
        context: "Met at the meetup.",
      }),
    ).toBe(
      "Ada Lovelace\nCompiler engineer\nBuilding symbolic math tools.\nMet at the meetup.",
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

describe("parseProfileUrl", () => {
  test("parses the three shared platforms from a plain profile URL", () => {
    expect(parseProfileUrl("https://instagram.com/mai.makes")).toEqual({
      platform: "instagram",
      handle: "mai.makes",
    });
    expect(parseProfileUrl("https://www.linkedin.com/in/mai-tran-8a91b2")).toEqual(
      { platform: "linkedin", handle: "mai-tran-8a91b2" },
    );
    expect(parseProfileUrl("https://x.com/mai_makes")).toEqual({
      platform: "x",
      handle: "mai_makes",
    });
  });

  test("twitter.com is the same platform as x.com", () => {
    expect(parseProfileUrl("https://twitter.com/mai_makes")).toEqual({
      platform: "x",
      handle: "mai_makes",
    });
  });

  test("tolerates the shapes share sheets actually hand over", () => {
    // www./m./mobile. subdomains, uppercase host, trailing slash.
    expect(parseProfileUrl("https://www.instagram.com/mai.makes/")).toEqual({
      platform: "instagram",
      handle: "mai.makes",
    });
    expect(parseProfileUrl("https://m.instagram.com/mai.makes")).toEqual({
      platform: "instagram",
      handle: "mai.makes",
    });
    expect(parseProfileUrl("https://mobile.twitter.com/mai_makes")).toEqual({
      platform: "x",
      handle: "mai_makes",
    });
    expect(parseProfileUrl("HTTPS://WWW.Instagram.COM/MaiMakes")).toEqual({
      platform: "instagram",
      handle: "MaiMakes",
    });
    // http and a missing scheme are both accepted.
    expect(parseProfileUrl("http://x.com/mai_makes")).toEqual({
      platform: "x",
      handle: "mai_makes",
    });
    expect(parseProfileUrl("  instagram.com/mai.makes  ")).toEqual({
      platform: "instagram",
      handle: "mai.makes",
    });
  });

  test("LinkedIn's country and lite hosts are the same profile", () => {
    // LinkedIn serves country-prefixed hosts to non-US members, and the app
    // shares whichever one the member is on.
    for (const host of ["vn", "uk", "de"]) {
      expect(
        parseProfileUrl(`https://${host}.linkedin.com/in/mai-tran-8a91b2`),
      ).toEqual({ platform: "linkedin", handle: "mai-tran-8a91b2" });
    }
    expect(
      parseProfileUrl("https://www.linkedin.com/mwlite/in/mai-tran-8a91b2"),
    ).toEqual({ platform: "linkedin", handle: "mai-tran-8a91b2" });
  });

  test("strips tracking query strings and fragments", () => {
    expect(
      parseProfileUrl("https://instagram.com/mai.makes/?igsh=abc123&utm=share"),
    ).toEqual({ platform: "instagram", handle: "mai.makes" });
    expect(
      parseProfileUrl("https://www.linkedin.com/in/mai-tran-8a91b2/#profile"),
    ).toEqual({ platform: "linkedin", handle: "mai-tran-8a91b2" });
  });

  test("keeps the handle's original case and drops a leading @", () => {
    expect(parseProfileUrl("https://x.com/@MaiMakes")).toEqual({
      platform: "x",
      handle: "MaiMakes",
    });
  });

  test("a post under the handle is content, not the profile", () => {
    // A shared tweet or Instagram post must not silently capture its author;
    // profile tabs like /tagged stay a person (pinned below).
    expect(parseProfileUrl("https://x.com/mai_makes/status/17999")).toBe(null);
    expect(parseProfileUrl("https://x.com/mai_makes/%73tatus/17999")).toBe(
      null,
    );
    expect(parseProfileUrl("https://instagram.com/mai.makes/p/Cxyz123")).toBe(
      null,
    );
    expect(
      parseProfileUrl("https://instagram.com/mai.makes/reel/Cxyz123/"),
    ).toBe(null);
  });

  test("reserved Instagram paths are content, not people", () => {
    for (const path of [
      "p/Cxyz123",
      "reel/Cxyz123",
      "reels/Cxyz123",
      "stories/mai.makes/123",
      "tv/Cxyz123",
      "explore/tags/hanoi",
      "accounts/login",
      "direct/inbox",
      "about",
    ]) {
      expect(parseProfileUrl(`https://instagram.com/${path}`)).toBe(null);
    }
  });

  test("reserved X paths are content, not people", () => {
    for (const path of [
      "i/flow/login",
      "home",
      "explore",
      "search?q=hanoi",
      "intent/follow",
      "hashtag/hanoi",
      "messages",
      "notifications",
      "settings/account",
      "compose/tweet",
      "share",
    ]) {
      expect(parseProfileUrl(`https://x.com/${path}`)).toBe(null);
    }
  });

  test("reserved segments match whole and case-insensitively", () => {
    expect(parseProfileUrl("https://instagram.com/REEL/Cxyz123")).toBe(null);
    expect(parseProfileUrl("https://x.com/I/flow/login")).toBe(null);
    // A handle that merely starts with a reserved word is still a person.
    expect(parseProfileUrl("https://x.com/ihateflying")).toEqual({
      platform: "x",
      handle: "ihateflying",
    });
    expect(parseProfileUrl("https://instagram.com/pho.reels")).toEqual({
      platform: "instagram",
      handle: "pho.reels",
    });
  });

  test("a percent-encoded reserved segment is still not a person", () => {
    expect(parseProfileUrl("https://instagram.com/%70/Cxyz123")).toBe(null);
    expect(parseProfileUrl("https://x.com/%69/flow/login")).toBe(null);
    // An encoded slash must not smuggle a second path segment into a handle.
    expect(parseProfileUrl("https://instagram.com/mai%2Fmakes")).toBe(null);
  });

  test("a deeper profile sub-path still identifies the person", () => {
    expect(
      parseProfileUrl(
        "https://www.linkedin.com/in/mai-tran-8a91b2/details/experience/",
      ),
    ).toEqual({ platform: "linkedin", handle: "mai-tran-8a91b2" });
    expect(parseProfileUrl("https://instagram.com/mai.makes/tagged/")).toEqual({
      platform: "instagram",
      handle: "mai.makes",
    });
  });

  test("a handle that is nothing but @ is empty, not a person", () => {
    expect(parseProfileUrl("https://x.com/@")).toBe(null);
  });

  test("LinkedIn is /in/<slug> only", () => {
    expect(parseProfileUrl("https://www.linkedin.com/company/convex")).toBe(
      null,
    );
    expect(parseProfileUrl("https://www.linkedin.com/posts/mai-tran-abc")).toBe(
      null,
    );
    expect(parseProfileUrl("https://www.linkedin.com/pub/mai-tran")).toBe(null);
    expect(parseProfileUrl("https://www.linkedin.com/feed/")).toBe(null);
    expect(parseProfileUrl("https://www.linkedin.com/jobs/view/123")).toBe(null);
    expect(parseProfileUrl("https://www.linkedin.com/in/")).toBe(null);
  });

  test("percent-decodes the slug, and refuses malformed encoding without throwing", () => {
    expect(
      parseProfileUrl("https://www.linkedin.com/in/nguy%E1%BB%85n-mai"),
    ).toEqual({ platform: "linkedin", handle: "nguy\u1ec5n-mai" });
    expect(parseProfileUrl("https://www.linkedin.com/in/%E0%A4%A")).toBe(null);
    expect(parseProfileUrl("https://instagram.com/%E0%A4%A")).toBe(null);
  });

  test("anything that is not one of the three profile shapes is null", () => {
    expect(parseProfileUrl("https://facebook.com/mai")).toBe(null);
    expect(parseProfileUrl("https://instagram.com.evil.example/mai")).toBe(null);
    expect(parseProfileUrl("https://instagram.com/")).toBe(null);
    expect(parseProfileUrl("https://x.com")).toBe(null);
    expect(parseProfileUrl("met at the conference")).toBe(null);
    expect(parseProfileUrl("")).toBe(null);
    expect(parseProfileUrl("   ")).toBe(null);
    expect(parseProfileUrl("ftp://instagram.com/mai.makes")).toBe(null);
  });

  test("round-trips the URLs deriveProfileUrl builds", () => {
    for (const handle of ["mai.makes", "ada_l", "caf\u00e9"]) {
      for (const platform of ["instagram", "x"] as const) {
        const url = deriveProfileUrl(platform, handle);
        expect(url).not.toBe(null);
        expect(parseProfileUrl(url as string)).toEqual({ platform, handle });
      }
    }
  });
});

describe("nameGuessFromSlug", () => {
  test("drops the trailing id junk and title-cases what is left", () => {
    expect(nameGuessFromSlug("mai-tran-8a91b2")).toBe("Mai Tran");
    expect(nameGuessFromSlug("john-doe")).toBe("John Doe");
  });

  test("only trailing digit segments are junk", () => {
    // A leading segment with digits is part of the name someone chose.
    expect(nameGuessFromSlug("m3-tran-8a91b2")).toBe("M3 Tran");
  });

  test("keeps accents from a percent-decoded slug", () => {
    expect(nameGuessFromSlug("nguy\u1ec5n-mai-8a91b2")).toBe(
      "Nguy\u1ec5n Mai",
    );
    expect(nameGuessFromSlug("\u0111\u1ee9c-anh")).toBe(
      "\u0110\u1ee9c Anh",
    );
  });

  test("nothing to guess yields an empty string", () => {
    expect(nameGuessFromSlug("8a91b2")).toBe("");
    expect(nameGuessFromSlug("8a91b2-7c4d")).toBe("");
    expect(nameGuessFromSlug("")).toBe("");
    expect(nameGuessFromSlug("   ")).toBe("");
    expect(nameGuessFromSlug("---")).toBe("");
  });

  test("empty segments from doubled or trailing hyphens do not leak spaces", () => {
    expect(nameGuessFromSlug("mai--tran-")).toBe("Mai Tran");
  });
});

describe("handleFromPath", () => {
  test("a single well-formed segment is a handle", () => {
    expect(handleFromPath("/maya")).toBe("maya");
    expect(handleFromPath("/mai_nguyen")).toBe("mai_nguyen");
    // A trailing slash is the same url to a person, so it is the same to us.
    expect(handleFromPath("/maya/")).toBe("maya");
  });

  test("the site's own root is not a handle", () => {
    expect(handleFromPath("/")).toBe(null);
    expect(handleFromPath("")).toBe(null);
  });

  // A card sits at the root, so it competes with every other top-level path.
  test("a name the site needs for itself is not a handle", () => {
    expect(handleFromPath("/privacy")).toBe(null);
    expect(handleFromPath("/terms")).toBe(null);
  });

  test("anything a handle could not be is not a handle", () => {
    expect(handleFromPath("/og.png")).toBe(null);
    expect(handleFromPath("/assets/index-abc.js")).toBe(null);
    expect(handleFromPath("/maya/notes")).toBe(null);
    // Too short, and too long.
    expect(handleFromPath("/ab")).toBe(null);
    expect(handleFromPath(`/${"a".repeat(25)}`)).toBe(null);
  });
});

describe("resolveView with a card path", () => {
  const base = {
    isAuthenticated: false,
    isLoading: false,
    hash: "",
    hasSessionHint: false,
  };

  // The stranger scanning a QR is the whole point of the page, and they arrive
  // signed out. Deciding the card from the path has to happen before the auth
  // checks, or a signed-out visitor waits behind Clerk on a splash and a
  // signed-in one is bounced to their own home.
  test("a card path wins over every auth state", () => {
    expect(resolveView({ ...base, pathname: "/maya" })).toBe("card");
    expect(
      resolveView({ ...base, pathname: "/maya", isLoading: true }),
    ).toBe("card");
    expect(
      resolveView({ ...base, pathname: "/maya", isAuthenticated: true }),
    ).toBe("card");
    expect(
      resolveView({
        ...base,
        pathname: "/maya",
        isLoading: true,
        hasSessionHint: true,
      }),
    ).toBe("card");
  });

  test("every other path routes exactly as it did before", () => {
    expect(resolveView({ ...base, pathname: "/" })).toBe("waitlist");
    // Hyphenated, so it is not a claimable handle and not a card. It used to
    // fall through to the waitlist, which is the bug reported from production:
    // somebody typing the most obvious url was told Haven has no sign-in.
    expect(resolveView({ ...base, pathname: "/sign-in" })).toBe("signin");
    expect(
      resolveView({ ...base, pathname: "/", isAuthenticated: true }),
    ).toBe("home");
    expect(
      resolveView({ ...base, pathname: "/", hash: "#/sign-in" }),
    ).toBe("signin");
  });
});

describe("legalDocFromPath", () => {
  test("names the two documents the App Store asks for", () => {
    expect(legalDocFromPath("/privacy")).toBe("privacy");
    expect(legalDocFromPath("/terms")).toBe("terms");
  });

  // A link typed by hand, or pasted with the trailing slash a browser adds,
  // has to land on the policy. App Review follows the url from App Store
  // Connect, and a 404 there is a rejection.
  test("forgives a trailing slash and any casing", () => {
    expect(legalDocFromPath("/privacy/")).toBe("privacy");
    expect(legalDocFromPath("/Privacy")).toBe("privacy");
    expect(legalDocFromPath("/TERMS/")).toBe("terms");
  });

  test("only the top level, and nothing else", () => {
    expect(legalDocFromPath("/")).toBeNull();
    expect(legalDocFromPath("/privacy/extra")).toBeNull();
    expect(legalDocFromPath("/maya")).toBeNull();
    expect(legalDocFromPath("/legal")).toBeNull();
  });
});

describe("resolveView with a legal path", () => {
  const base = {
    isAuthenticated: false,
    isLoading: false,
    hash: "",
    hasSessionHint: false,
  };

  // Same reasoning as the card route above: the reviewer opening this url is
  // signed out, and a signed-in visitor who taps "Privacy" wants the policy
  // rather than a bounce to their own home.
  test("a legal path wins over every auth state", () => {
    expect(resolveView({ ...base, pathname: "/privacy" })).toBe("legal");
    expect(
      resolveView({ ...base, pathname: "/terms", isAuthenticated: true }),
    ).toBe("legal");
    expect(
      resolveView({
        ...base,
        pathname: "/privacy",
        isLoading: true,
        hasSessionHint: true,
      }),
    ).toBe("legal");
  });

  // The two routes cannot both own "/privacy", and the handle list is what
  // keeps them apart. If somebody ever unreserves the word, this fails here
  // rather than by quietly serving a stranger's card as the privacy policy.
  test("no one can claim these paths as a handle", () => {
    expect(handleFromPath("/privacy")).toBeNull();
    expect(handleFromPath("/terms")).toBeNull();
  });
});

describe("the sign-in paths a person actually types", () => {
  const base = {
    isAuthenticated: false,
    isLoading: false,
    hash: "",
    hasSessionHint: false,
  };

  // Reported from production: inhavens.com/signin and /signup both showed the
  // waitlist. Every one of these words is reserved, so none could ever be
  // somebody's card, and landing on the waitlist told a person who typed the
  // most obvious url that Haven has no sign-in at all.
  test("every spelling of sign-in reaches the sign-in view", () => {
    for (const path of [
      "/signin",
      "/sign-in",
      "/signup",
      "/sign-up",
      "/login",
      "/SignIn",
      "/sign-up/",
    ]) {
      expect(resolveView({ ...base, pathname: path })).toBe("signin");
    }
  });

  // Clerk owns sub-paths under the component once it is mounted there.
  test("Clerk's own sub-steps stay on the sign-in view", () => {
    expect(resolveView({ ...base, pathname: "/sign-in/factor-one" })).toBe(
      "signin",
    );
    expect(
      resolveView({ ...base, pathname: "/sign-up/verify-email-address" }),
    ).toBe("signin");
  });

  // A signed-in visitor who lands on /signin should not be bounced to the
  // waitlist, and should not be shown a sign-in form either.
  test("a signed-in visitor on a sign-in path goes home", () => {
    expect(
      resolveView({ ...base, pathname: "/signin", isAuthenticated: true }),
    ).toBe("home");
  });

  test("no one can claim these as a handle", () => {
    for (const path of ["/signin", "/signup", "/login"]) {
      expect(handleFromPath(path)).toBeNull();
    }
  });
});

describe("sitePageFromPath", () => {
  test("names every page the site owns above the handles", () => {
    expect(sitePageFromPath("/privacy")).toBe("privacy");
    expect(sitePageFromPath("/terms")).toBe("terms");
    expect(sitePageFromPath("/support")).toBe("support");
  });

  test("forgives a trailing slash and any casing", () => {
    expect(sitePageFromPath("/support/")).toBe("support");
    expect(sitePageFromPath("/Support")).toBe("support");
    expect(sitePageFromPath("/SUPPORT/")).toBe("support");
  });

  // "supporting" is a perfectly claimable handle, and a prefix match would eat
  // it. So would any nested path.
  test("only the top level, and nothing else", () => {
    expect(sitePageFromPath("/")).toBeNull();
    expect(sitePageFromPath("/supporting")).toBeNull();
    expect(sitePageFromPath("/support/extra")).toBeNull();
    expect(sitePageFromPath("/help")).toBeNull();
  });

  // legalDocFromPath is the narrower question -- which document LegalPage
  // should render -- and support is not one, so it must keep saying null.
  test("support is a site page but not a legal document", () => {
    expect(legalDocFromPath("/support")).toBeNull();
  });
});

describe("resolveView with a support path", () => {
  const base = {
    isAuthenticated: false,
    isLoading: false,
    hash: "",
    hasSessionHint: false,
  };

  // The App Store Support URL is opened by a reviewer with no session, and by
  // people who are locked out of theirs -- which is the single most likely
  // reason somebody goes looking for support at all. It cannot require auth.
  test("a support path wins over every auth state", () => {
    expect(resolveView({ ...base, pathname: "/support" })).toBe("support");
    expect(
      resolveView({ ...base, pathname: "/support", isAuthenticated: true }),
    ).toBe("support");
    expect(
      resolveView({
        ...base,
        pathname: "/support",
        isLoading: true,
        hasSessionHint: true,
      }),
    ).toBe("support");
  });

  test("no one can claim it as a handle", () => {
    expect(handleFromPath("/support")).toBeNull();
  });
});

describe("buildDossier", () => {
  test("puts the card on one heading line and the notes underneath", () => {
    expect(
      buildDossier(3, {
        name: "Ada Lovelace",
        role: "Compiler engineer",
        company: "Analytical Engines",
        cityName: "Sai Gon",
        platforms: ["x", "instagram"],
        headline: "Building symbolic math tools",
        bio: "Works on compilers and their proofs.",
        memories: [
          { text: "met at the Founder Inc dinner", createdAt: 1_750_000_000_000 },
          { text: "works on an infinite-context database", createdAt: 1_752_000_000_000 },
        ],
      }),
    ).toBe(
      [
        "#3 Ada Lovelace | Compiler engineer at Analytical Engines | Sai Gon | x, instagram",
        "Building symbolic math tools",
        "Works on compilers and their proofs.",
        "- 2025-06-15: met at the Founder Inc dinner",
        "- 2025-07-08: works on an infinite-context database",
      ].join("\n"),
    );
  });

  test("a person with only a name still gets a usable heading", () => {
    // The prompt refers to people by ref, so a bare row must never collapse
    // into a line the model cannot point at.
    expect(buildDossier(1, { name: "Ada Lovelace" })).toBe("#1 Ada Lovelace");
  });

  test("drops empty parts rather than leaving separators behind", () => {
    expect(
      buildDossier(2, {
        name: "Ada",
        company: "Analytical Engines",
        cityName: "  ",
        headline: "",
        platforms: [],
        memories: [],
      }),
    ).toBe("#2 Ada | Analytical Engines");
  });
});
