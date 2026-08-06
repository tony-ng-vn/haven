import { describe, expect, test } from "vitest";
import {
  handleDisplayValue,
  handleIndexKeys,
  handleValueKey,
  hasPhoneDigit,
  isPhoneNumberPlatform,
} from "./handleKeys";

// This module is the frozen identity contract every handle write path folds
// through, so its rules are pinned here rather than only observed through the
// mutations that call it.

describe("handleDisplayValue", () => {
  test("trims and drops the leading at signs a share carries", () => {
    expect(handleDisplayValue("  @@mai.makes  ")).toBe("mai.makes");
  });

  test("keeps the casing the person typed", () => {
    expect(handleDisplayValue("@Mai.Makes")).toBe("Mai.Makes");
  });

  test("leaves an at sign that is not a prefix alone", () => {
    expect(handleDisplayValue("mai@makes")).toBe("mai@makes");
  });
});

describe("handleValueKey", () => {
  test("folds the shapes of one account onto one key", () => {
    expect(handleValueKey("@Mai.Makes")).toBe(handleValueKey("mai.makes"));
  });

  test("keeps different accounts apart", () => {
    expect(handleValueKey("mai.makes")).not.toBe(handleValueKey("maimakes"));
  });
});

describe("handleIndexKeys", () => {
  test("folds the platform a legacy row stored unnormalized", () => {
    expect(handleIndexKeys({ platform: " Instagram ", value: "@Mai.Makes" })).toEqual(
      { platform: "instagram", valueKey: "mai.makes" },
    );
  });
});

// The one seam where iOS (already E.164 via PhoneNumberKit), a web entry
// normalized with browser region evidence, and a bare digit string from an
// older row or a capture path all have to land on the same identity.
describe("handleValueKey phone and whatsapp fold", () => {
  test("a value with its own country code keys to its E.164 form regardless of formatting", () => {
    expect(handleValueKey("+1 415 555 0123", "phone")).toBe("+14155550123");
    expect(handleValueKey("+14155550123", "phone")).toBe("+14155550123");
    expect(handleValueKey("+1 415 555 0123", "whatsapp")).toBe("+14155550123");
  });

  test("a foreign country code keys under its own country, never +1", () => {
    expect(handleValueKey("+84 90 123 4567", "phone")).toBe("+84901234567");
    expect(handleValueKey("+84 90 123 4567", "phone")).not.toMatch(/^\+1/);
  });

  test("a bare number with no country-code evidence folds to its digits, not a guessed region", () => {
    expect(handleValueKey("4155550123", "phone")).toBe("4155550123");
    expect(handleValueKey("(415) 555-0123", "phone")).toBe("4155550123");
    expect(handleValueKey("4155550123", "whatsapp")).toBe("4155550123");
  });

  test("a plus sign that carries no real country code also falls back to digits", () => {
    expect(handleValueKey("+0000", "phone")).toBe("0000");
  });

  test("two unreadable phone entries stay two identities instead of colliding on an empty digits key", () => {
    const a = handleValueKey("call me", "phone");
    const b = handleValueKey("ask mai", "phone");
    expect(a).not.toBe("");
    expect(b).not.toBe("");
    expect(a).not.toBe(b);
  });

  test("the platform switch is what turns the fold on -- unset platform keeps the plain fold", () => {
    expect(handleValueKey("+1 415 555 0123")).toBe("+1 415 555 0123");
  });
});

describe("handleValueKey leaves every other platform untouched", () => {
  test("instagram, x and linkedin still fold by trim, strip-@, lowercase alone", () => {
    expect(handleValueKey("@Mai.Makes", "instagram")).toBe("mai.makes");
    expect(handleValueKey("Mai_Makes", "x")).toBe("mai_makes");
    expect(handleValueKey("Mai-Nguyen-123", "linkedin")).toBe("mai-nguyen-123");
  });
});

describe("handleIndexKeys threads the platform into the phone fold", () => {
  test("differently formatted phone entries land on one index row", () => {
    expect(handleIndexKeys({ platform: "phone", value: "+1 415 555 0123" })).toEqual(
      { platform: "phone", valueKey: "+14155550123" },
    );
    expect(handleIndexKeys({ platform: " Phone ", value: "+14155550123" })).toEqual(
      { platform: "phone", valueKey: "+14155550123" },
    );
  });
});

describe("isPhoneNumberPlatform", () => {
  test("phone and whatsapp are number platforms, whichever case or spacing", () => {
    expect(isPhoneNumberPlatform("phone")).toBe(true);
    expect(isPhoneNumberPlatform(" WhatsApp ")).toBe(true);
  });

  test("every other platform is not", () => {
    expect(isPhoneNumberPlatform("instagram")).toBe(false);
    expect(isPhoneNumberPlatform("x")).toBe(false);
  });
});

describe("hasPhoneDigit", () => {
  test("a value with at least one digit passes", () => {
    expect(hasPhoneDigit("+1 415 555 0123")).toBe(true);
    expect(hasPhoneDigit("call 0")).toBe(true);
  });

  // The exact collision this exists to catch: two different unreadable
  // pastes that would otherwise fold to the same plain-lowercase key.
  test("a value with no digit at all fails, whatever the case", () => {
    expect(hasPhoneDigit("unknown")).toBe(false);
    expect(hasPhoneDigit("Unknown")).toBe(false);
    expect(hasPhoneDigit("ask mai")).toBe(false);
  });
});
