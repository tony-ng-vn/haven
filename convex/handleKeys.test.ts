import { describe, expect, test } from "vitest";
import {
  handleDisplayValue,
  handleIndexKeys,
  handleValueKey,
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
