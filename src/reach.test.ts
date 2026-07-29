import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import {
  REACH_PLATFORMS,
  isPhoneNumber,
  reachLabel,
  reachPlaceholder,
  reachUrl,
  reachValue,
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

  // A number is kept as typed. iOS folds one to E.164 with libphonenumber,
  // which needs that whole library to do honestly, and reading a number back
  // is already handled where it matters.
  test("a number is kept as it was written", () => {
    expect(reachValue("phone", "  +84 90 123 4567 ")).toBe("+84 90 123 4567");
    expect(reachValue("whatsapp", "+84 90 123 4567")).toBe("+84 90 123 4567");
    expect(reachUrl("phone", reachValue("phone", "+84 90 123 4567"))).toBe(
      "tel:+84901234567",
    );
  });

  test("what is stored is what opens again", () => {
    for (const raw of [
      "https://instagram.com/mai.makes",
      "instagram.com/mai.makes",
      "@mai.makes",
      "mai.makes",
    ]) {
      expect(reachUrl("instagram", reachValue("instagram", raw))).toBe(
        "https://instagram.com/mai.makes",
      );
    }
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
