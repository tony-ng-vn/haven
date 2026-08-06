import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import {
  REACH_PLATFORMS,
  isLinkedInHandleStale,
  isPhoneNumber,
  normalizePhoneEntry,
  reachLabel,
  reachPlaceholder,
  reachUrl,
  reachValue,
  samePlatform,
} from "./reach";

// The web mirror of ios/Haven/Directory/PersonReach.swift, and the tests that
// keep the two honest. Nothing imports across the platform boundary, so the
// last block here reads the Swift file off disk the way designTokens.test.ts
// reads the palette: the addresses a handle turns into are one decision, and a
// person who saved "mai.makes" on their phone must land on the same page from
// the web.

describe("what a handle turns into", () => {
  test("every platform Haven offers has an address", () => {
    expect(reachUrl("instagram", "mai.makes")).toBe(
      "https://instagram.com/mai.makes",
    );
    expect(reachUrl("x", "maimakes")).toBe("https://x.com/maimakes");
    expect(reachUrl("linkedin", "mai-nguyen-8a91b2")).toBe(
      "https://linkedin.com/in/mai-nguyen-8a91b2",
    );
    expect(reachUrl("telegram", "maimakes")).toBe("https://t.me/maimakes");
    expect(reachUrl("phone", "+84901234567")).toBe("tel:+84901234567");
    expect(reachUrl("whatsapp", "+84901234567")).toBe(
      "https://wa.me/84901234567",
    );
  });

  // Rows written before the rename still say twitter, and the person behind
  // them has not moved.
  test("the old name for X still goes to X", () => {
    expect(reachLabel("twitter")).toBe("X");
    expect(reachUrl("twitter", "maimakes")).toBe("https://x.com/maimakes");
  });

  // An X username can be changed by its owner; the numeric id behind it
  // cannot -- so a handle carrying one links by id, which survives a rename
  // the username address below could not.
  test("an X handle with a platform id links by id, not by username", () => {
    expect(reachUrl("x", "maimakes", "1234567890")).toBe(
      "https://x.com/intent/user?user_id=1234567890",
    );
    // A legacy row still saying "twitter" gets the same rename-proof link.
    expect(reachUrl("twitter", "maimakes", "1234567890")).toBe(
      "https://x.com/intent/user?user_id=1234567890",
    );
  });

  test("an X handle with no platform id falls back to the username address", () => {
    expect(reachUrl("x", "maimakes", undefined)).toBe(
      "https://x.com/maimakes",
    );
    expect(reachUrl("x", "maimakes", "")).toBe("https://x.com/maimakes");
  });

  // Only X carries a rename-proof id today: a platformId on any other
  // platform's handle must not change what it links to.
  test("a platform id is ignored on every platform but X", () => {
    expect(reachUrl("instagram", "mai.makes", "ig_12345")).toBe(
      "https://instagram.com/mai.makes",
    );
    expect(reachUrl("linkedin", "mai-nguyen-8a91b2", "urn:li:person:abc")).toBe(
      "https://linkedin.com/in/mai-nguyen-8a91b2",
    );
  });

  // A number is dialled, not browsed: a stored number is one number however it
  // was typed, and tel: does not want its spaces.
  test("a number keeps its digits and its country plus, nothing else", () => {
    expect(reachUrl("phone", "+84 90 123 4567")).toBe("tel:+84901234567");
    expect(reachUrl("phone", "(090) 123-4567")).toBe("tel:0901234567");
    // wa.me addresses a number without its plus.
    expect(reachUrl("whatsapp", "+84 90 123 4567")).toBe(
      "https://wa.me/84901234567",
    );
    // Nothing dialable in it, so there is nothing to promise.
    expect(reachUrl("phone", "call me")).toBeNull();
    expect(reachUrl("whatsapp", "ask mai")).toBeNull();
  });

  // Null is an ordinary answer. A handle on a platform Haven has never heard
  // of is a real way to reach somebody, so the label keeps what was typed --
  // dressing "signal" up as something else would be a claim Haven cannot back.
  test("a platform Haven does not know keeps its name and gets no link", () => {
    expect(reachLabel("signal")).toBe("signal");
    expect(reachLabel(" Signal ")).toBe(" Signal ");
    expect(reachUrl("signal", "mai.99")).toBeNull();
  });

  test("a platform is read past its spacing and its capitals", () => {
    expect(reachLabel(" Instagram ")).toBe("Instagram");
    expect(reachUrl(" WhatsApp ", "0901234567")).toBe(
      "https://wa.me/0901234567",
    );
  });

  test("an empty handle is no handle", () => {
    expect(reachUrl("instagram", "")).toBeNull();
    expect(reachUrl("instagram", "   ")).toBeNull();
    expect(reachUrl("phone", " ")).toBeNull();
    // The value is trimmed before it is used, not rejected for its edges.
    expect(reachUrl("instagram", "  mai.makes  ")).toBe(
      "https://instagram.com/mai.makes",
    );
  });

  // Swift escapes with .urlPathAllowed, which keeps more than
  // encodeURIComponent does. A handle carrying one of the characters they
  // disagree on is the whole point of this test.
  test("a handle that needs escaping is escaped the way iOS escapes it", () => {
    expect(reachUrl("instagram", "mai makes")).toBe(
      "https://instagram.com/mai%20makes",
    );
    expect(reachUrl("telegram", "mai+makes")).toBe("https://t.me/mai+makes");
    expect(reachUrl("linkedin", "mai/makes")).toBe(
      "https://linkedin.com/in/mai/makes",
    );
    expect(reachUrl("instagram", "mai?makes#1")).toBe(
      "https://instagram.com/mai%3Fmakes%231",
    );
    // "mai cafe" with an acute e, written escaped to keep the source ASCII:
    // a non-ASCII handle percent-encodes as UTF-8 on both platforms.
    expect(reachUrl("instagram", "mai caf\u00e9")).toBe(
      "https://instagram.com/mai%20caf%C3%A9",
    );
  });

  test("the field knows when it is asking for a number", () => {
    expect(isPhoneNumber("phone")).toBe(true);
    expect(isPhoneNumber(" WhatsApp ")).toBe(true);
    expect(isPhoneNumber("instagram")).toBe(false);
    expect(isPhoneNumber("telegram")).toBe(false);
    expect(isPhoneNumber("signal")).toBe(false);
    expect(reachPlaceholder("phone")).toBe("Their number");
    expect(reachPlaceholder("instagram")).toBe(
      "Paste a link or type the handle",
    );
  });
});

// The field says "Paste a link or type the handle", so pasting a link has to
// work. Storing one verbatim is what turns a handle into a dead address:
// "https://instagram.com/mai.makes" saved as-is opens
// instagram.com/https://instagram.com/mai.makes.
describe("what gets stored", () => {
  test("a pasted profile link is folded to the handle", () => {
    expect(reachValue("instagram", "https://instagram.com/mai.makes")).toBe(
      "mai.makes",
    );
    expect(reachValue("linkedin", "linkedin.com/in/mai-nguyen-8a91b2/")).toBe(
      "mai-nguyen-8a91b2",
    );
    // A query or a fragment on a profile link is not part of the handle.
    expect(reachValue("telegram", "https://t.me/maimakes?start=hello")).toBe(
      "maimakes",
    );
    // The second address a platform answers to still gets found.
    expect(reachValue("x", "https://twitter.com/maimakes")).toBe("maimakes");
    expect(reachValue("x", "HTTPS://X.COM/maimakes")).toBe("maimakes");
  });

  test("a typed handle keeps its shape, minus the at-sign", () => {
    expect(reachValue("instagram", "  @mai.makes  ")).toBe("mai.makes");
    expect(reachValue("x", "maimakes")).toBe("maimakes");
    // A platform Haven does not know has no address to strip, so nothing is
    // taken off it beyond the spacing.
    expect(reachValue("signal", "  mai.99  ")).toBe("mai.99");
  });

  // A number with its own country code folds to E.164, same as iOS folds one
  // with PhoneNumberKit -- a person saved from either platform lands on the
  // same key. Something that does not parse as a valid number is kept as
  // typed rather than guessed at.
  test("a number with a country code is folded to E.164", () => {
    expect(reachValue("phone", "  +84 90 123 4567 ")).toBe("+84901234567");
    expect(reachValue("whatsapp", "+84 90 123 4567")).toBe("+84901234567");
    // Non-null asserted deliberately: a valid number is never refused, and
    // the assertion above this line is what proves it.
    expect(reachUrl("phone", reachValue("phone", "+84 90 123 4567")!)).toBe(
      "tel:+84901234567",
    );
  });

  // A digitless value with digits elsewhere in it (a local number with no
  // country code) is still kept as typed rather than guessed at -- only the
  // total absence of a digit is refused, below.
  test("something with digits that does not parse as a number is kept exactly as typed", () => {
    expect(reachValue("phone", "555-1234")).toBe("555-1234");
  });

  // R1 (identity brief, round 2): a phone/whatsapp value with no digit at
  // all folds through handleValueKey's own lowercase fallback server-side,
  // so two different unreadable entries ("call me" from one person, "ask
  // mai" from another) could otherwise collide on the same identity key.
  // Refusing here, the same way convex/handleKeys.ts's hasPhoneDigit gates
  // the server write, is the client-side half of that -- storing wreckage
  // that later merges two strangers is worse than refusing the paste.
  test("a phone or whatsapp value with no digit at all is refused, not stored", () => {
    expect(reachValue("phone", "call me")).toBeNull();
    expect(reachValue("whatsapp", "ask mai")).toBeNull();
  });

  test("what is stored is what opens again", () => {
    for (const raw of [
      "https://instagram.com/mai.makes",
      "instagram.com/mai.makes",
      "@mai.makes",
      "mai.makes",
    ]) {
      const stored = reachValue("instagram", raw);
      // Checked rather than asserted away: a refusal here would be the bug,
      // and toBe(null) reads clearer in the failure than a thrown TypeError.
      expect(stored).not.toBeNull();
      expect(reachUrl("instagram", stored as string)).toBe(
        "https://instagram.com/mai.makes",
      );
    }
  });
});

// The web's half of the identity fix: the server (convex/handleKeys.ts)
// refuses to guess a region for a bare number, so a number typed without its
// country code has to arrive already carrying one -- the browser's own
// locale is the region evidence the server does not have.
describe("normalizePhoneEntry", () => {
  test("three shapes of the same US number fold to one E.164 value with US region evidence", () => {
    const shapes = ["(415) 555-0123", "+1 415 555 0123", "4155550123"];
    const normalized = shapes.map((raw) => normalizePhoneEntry(raw, "US"));
    expect(new Set(normalized).size).toBe(1);
    expect(normalized[0]).toBe("+14155550123");
  });

  test("a number already carrying its own country code ignores the region", () => {
    expect(normalizePhoneEntry("+84 90 123 4567", "US")).toBe("+84901234567");
  });

  test("no region and no country code in the string leaves it unparsed, so it is kept as typed", () => {
    expect(normalizePhoneEntry("4155550123")).toBe("4155550123");
  });

  test("something that never parses as a number is returned untouched", () => {
    expect(normalizePhoneEntry("call me", "US")).toBe("call me");
  });
});

// reachValue calls normalizePhoneEntry with the browser's own region, which
// this test environment reports as "en-US" -- the same evidence a real
// browser would give a real person typing a local number.
describe("reachValue folds a phone entry using the browser's region", () => {
  test("the three US shapes reach one identical stored value with no region passed explicitly", () => {
    const stored = [
      "(415) 555-0123",
      "+1 415 555 0123",
      "4155550123",
    ].map((raw) => reachValue("phone", raw));
    expect(new Set(stored).size).toBe(1);
    expect(stored[0]).toBe("+14155550123");
  });
});

// wa.me needs the number without its leading plus; digitsOnly already strips
// it, this just pins that an E.164-shaped value survives the same way.
describe("a wa.me link built from an E.164 value", () => {
  test("contains digits only", () => {
    const url = reachUrl("whatsapp", "+14155550123");
    expect(url).toBe("https://wa.me/14155550123");
    expect(url).toMatch(/^https:\/\/wa\.me\/\d+$/);
  });
});

// Pinned to the iOS source, the way designTokens.test.ts pins the palette and
// iosProjectSettings.test.ts pins what the app claims to run on. Every one of
// these parses the Swift first and asserts it found something, because a regex
// that quietly matches nothing turns the whole block into a green no-op.
describe("the iOS file this mirrors", () => {
  const swift = readFileSync(
    "ios/Haven/Directory/PersonReach.swift",
    "utf8",
  );

  /// The slice of the Swift between two landmarks, so one switch's cases
  /// cannot be read as another's.
  function section(from: string, to: string): string {
    const start = swift.indexOf(from);
    expect(start, `PersonReach.swift no longer has "${from}"`).toBeGreaterThan(
      -1,
    );
    const end = swift.indexOf(to, start);
    expect(end, `PersonReach.swift no longer has "${to}"`).toBeGreaterThan(
      start,
    );
    return swift.slice(start, end);
  }

  /// Every `case .a, .b: return "value"` in a switch, one entry per case.
  function returnedStrings(block: string): Map<string, string> {
    const found = new Map<string, string>();
    for (const [, cases, value] of block.matchAll(
      /case ([^:{}]+): return "([^"]*)"/g,
    )) {
      for (const name of cases.split(",")) {
        found.set(name.trim().replace(/^\./, ""), value);
      }
    }
    return found;
  }

  test("offers the same platforms, in the same order", () => {
    const declared = swift.match(/static let offerable = \[([^\]]*)\]/);
    expect(declared, "PersonReach.offerable is no longer a literal").not.toBeNull();
    const offerable = declared![1]
      .split(",")
      .map((entry) => entry.trim().replace(/^"|"$/g, ""));
    expect(offerable).toEqual([...REACH_PLATFORMS]);
    // twitter is readable but not offerable: it is the old name for a platform
    // that already has one, and offering both would make two of one platform.
    expect(offerable).not.toContain("twitter");
  });

  test("calls each platform the same thing", () => {
    const labels = returnedStrings(
      section("var label: String {", "var addressPrefix"),
    );
    expect(labels.size).toBe(7);
    for (const [platform, label] of labels) {
      expect(reachLabel(platform), `${platform} reads differently`).toBe(label);
    }
  });

  test("sends each platform to the same address", () => {
    const prefixes = returnedStrings(
      section("var addressPrefix: String? {", "private static func known"),
    );
    // The five with a web address; whatsapp and phone return nil there because
    // their value is a number rather than part of an address.
    expect(prefixes.size).toBe(5);
    for (const [platform, prefix] of prefixes) {
      expect(reachUrl(platform, "someone"), `${platform} lands elsewhere`).toBe(
        `https://${prefix}someone`,
      );
    }
  });

  test("dials and messages a number the same way", () => {
    expect(swift).toContain('URL(string: "tel:\\(dialable)")');
    expect(swift).toContain('URL(string: "https://wa.me/\\(digits)")');
  });

  // The folding half of ContactValue.swift, which is what makes the placeholder
  // above true. Its other half -- each platform's character and length rules --
  // is deliberately not mirrored: on iOS those exist to keep Continue disabled,
  // and the web has nothing to disable.
  test("digs a handle out of the same addresses", () => {
    const contact = readFileSync(
      "ios/Haven/Onboarding/ContactValue.swift",
      "utf8",
    );
    const parsers = {
      instagram: "instagramHandle",
      x: "xHandle",
      linkedin: "linkedInHandle",
      telegram: "telegramHandle",
    };
    for (const [platform, parser] of Object.entries(parsers)) {
      const at = contact.indexOf(`static func ${parser}(`);
      expect(at, `ContactValue.swift no longer has ${parser}`).toBeGreaterThan(
        -1,
      );
      const call = contact
        .slice(at)
        .match(/handle\(in: raw, after: \[([^\]]*)\]\)/);
      expect(call, `${parser} no longer folds an address`).not.toBeNull();
      const hosts = call![1]
        .split(",")
        .map((host) => host.trim().replace(/^"|"$/g, ""));
      expect(hosts.length).toBeGreaterThan(0);
      for (const host of hosts) {
        expect(
          reachValue(platform, `https://${host}maimakes`),
          `${platform} does not know ${host}`,
        ).toBe("maimakes");
      }
    }
  });

  test("asks for a handle with the same words", () => {
    expect(swift).toContain('"Their number" : "Paste a link or type the handle"');
    expect(reachPlaceholder("phone")).toBe("Their number");
    expect(reachPlaceholder("x")).toBe("Paste a link or type the handle");
  });
});

describe("samePlatform", () => {
  test("folds like every other platform read", () => {
    // The server stores what was sent, so a row can say "Instagram" while
    // preferredPlatform says "instagram". A raw === would silently fail to
    // mark the row the person actually chose.
    expect(samePlatform("instagram", "Instagram")).toBe(true);
    expect(samePlatform(" X ", "x")).toBe(true);
    expect(samePlatform("instagram", "x")).toBe(false);
  });

  test("nothing preferred marks nothing", () => {
    expect(samePlatform("instagram", undefined)).toBe(false);
  });
});

describe("reachValue refuses an address it cannot read a handle out of", () => {
  // Every one of these used to store the literal handle "https:", which is not
  // a dead link but an identity collision: handleValueKey folds it to the same
  // key for every unreadable paste, so two unrelated people would land on one
  // (userId, platform, valueKey) row in personHandles. iOS refuses all of them.
  const unreadable: Array<[string, string]> = [
    ["linkedin", "https://www.linkedin.com/pub/mai-nguyen/1/2a/3b"],
    ["linkedin", "https://www.linkedin.com/mwlite/in/mai-nguyen"],
    ["instagram", "https://instagram.com/https://instagram.com/mai.makes"],
    ["instagram", "https://instagram.com"],
    ["instagram", "instagram.com"],
    ["instagram", "www.instagram.com"],
    ["instagram", "https://instagram.com/"],
    ["instagram", ""],
    ["instagram", "   "],
  ];
  for (const [platform, raw] of unreadable) {
    test(`${platform} refuses ${JSON.stringify(raw)}`, () => {
      expect(reachValue(platform, raw)).toBeNull();
    });
  }

  test("what it refuses can never reach reachUrl as a doubled address", () => {
    for (const [platform, raw] of unreadable) {
      const stored = reachValue(platform, raw);
      if (stored === null) continue;
      expect(reachUrl(platform, stored)).not.toMatch(/https:\/\/[^/]+\/(https?:|[^/]*\.(com|me)\/)/);
    }
  });

  test("a handle it can read still round-trips", () => {
    // The guard must not become a wall: these are the ordinary pastes.
    expect(reachValue("instagram", "https://www.instagram.com/mai.makes/")).toBe("mai.makes");
    expect(reachValue("instagram", "@mai.makes")).toBe("mai.makes");
    expect(reachValue("instagram", "mai.makes")).toBe("mai.makes");
    expect(reachValue("instagram", "INSTAGRAM.COM/Mai")).toBe("Mai");
    expect(reachValue("x", "https://twitter.com/ada_l")).toBe("ada_l");
    expect(reachValue("linkedin", "https://www.linkedin.com/in/ada-lovelace-123/")).toBe("ada-lovelace-123");
    expect(reachValue("telegram", "https://t.me/ada")).toBe("ada");
    expect(reachValue("telegram", "t.me/+invite")).toBe("+invite");
    // Unknown platform passes through: Haven does not know a rule for it.
    expect(reachValue("signal", "whatever they typed")).toBe("whatever they typed");
    // A number with a country code folds; the fold is still a round-trip.
    expect(reachValue("phone", "+84 90 123 4567")).toBe("+84901234567");
  });

  test("a length-changing fold does not shift where the handle starts", () => {
    // toLowerCase can lengthen a string (U+0130), so an index taken from the
    // lowercased copy cannot be sliced out of the original.
    expect(reachValue("instagram", "İ instagram.com/mai.makes")).not.toBe("ai.makes");
  });
});

describe("reachUrl escaping", () => {
  test("a colon is escaped, because Swift escapes it too", () => {
    // Measured against Foundation's .urlPathAllowed rather than read off a
    // table: both sides escape ":", so leaving it raw here would have made the
    // two platforms open different addresses for one handle.
    expect(reachUrl("instagram", "mai:co")).toBe("https://instagram.com/mai%3Aco");
  });

  test("is total, even on a lone surrogate", () => {
    expect(reachUrl("instagram", "mai\uD83D")).toBeNull();
  });
});

describe("isLinkedInHandleStale", () => {
  const now = Date.UTC(2026, 7, 4);
  const sixMonthsMs = 1000 * 60 * 60 * 24 * 30 * 6;

  test("a linkedin handle saved more than six months ago is stale", () => {
    expect(isLinkedInHandleStale("linkedin", now - sixMonthsMs - 1, now)).toBe(true);
  });

  test("a linkedin handle saved within the last six months is not stale", () => {
    expect(isLinkedInHandleStale("linkedin", now - sixMonthsMs + 1, now)).toBe(false);
    expect(isLinkedInHandleStale("linkedin", now, now)).toBe(false);
  });

  // Legacy rows saved before addedAt existed must not read as stale by
  // default -- a false "still the right link?" on a handle nobody can date
  // is worse than staying quiet.
  test("no addedAt at all is never stale", () => {
    expect(isLinkedInHandleStale("linkedin", undefined, now)).toBe(false);
  });

  // The reclaim window is LinkedIn's own policy; no other platform recycles
  // handles this way.
  test("only linkedin is ever flagged, however old another platform's handle is", () => {
    expect(isLinkedInHandleStale("instagram", now - sixMonthsMs - 1, now)).toBe(
      false,
    );
    expect(isLinkedInHandleStale("x", now - sixMonthsMs - 1, now)).toBe(false);
  });

  test("defaults to the real clock when now is not given", () => {
    expect(isLinkedInHandleStale("linkedin", Date.now() - sixMonthsMs - 1)).toBe(
      true,
    );
  });
});
