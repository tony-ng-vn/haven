import { describe, expect, test } from "vitest";
import { isReservedHandle } from "./handleNames";

describe("isReservedHandle", () => {
  // The two the App Store needs before Haven can be submitted at all. If one of
  // these were claimable, the page review asks for would be someone's card.
  test("the legal pages the App Store requires are held back", () => {
    expect(isReservedHandle("privacy")).toBe(true);
    expect(isReservedHandle("terms")).toBe(true);
  });

  test("the site's own routes are held back", () => {
    for (const name of [
      "signin",
      "join",
      "waitlist",
      "preview",
      "festival",
      "home",
      "settings",
    ]) {
      expect(isReservedHandle(name)).toBe(true);
    }
  });

  // /landing used to be a distinct preview page; it is retired now (see
  // resolveView in src/lib.ts) and just falls through to the front door. The
  // word stays reserved anyway: if it were claimable, a signed-up person's
  // own card would shadow that fallthrough forever -- the same trap
  // privacy/terms/support are held back against.
  test("the retired /landing path is still held back", () => {
    expect(isReservedHandle("landing")).toBe(true);
  });

  // /sky and /waitlist are Landing2's own two button destinations (see
  // isSkyPath / isWaitlistPath in src/lib.ts). Same shadowing trap as above.
  test("the sky and waitlist pages are held back", () => {
    expect(isReservedHandle("sky")).toBe(true);
    expect(isReservedHandle("waitlist")).toBe(true);
  });

  test("the brand is held back", () => {
    expect(isReservedHandle("haven")).toBe(true);
    expect(isReservedHandle("inhavens")).toBe(true);
  });

  // Reserving is a cost paid by real people, so it has to stay narrow enough
  // that an ordinary name still goes through.
  test("an ordinary handle is not reserved", () => {
    for (const name of ["maya", "tony", "mai_nguyen", "ada99"]) {
      expect(isReservedHandle(name)).toBe(false);
    }
  });

  // claimHandle normalizes before it validates, but the web router reads
  // straight off the url, so this has to hold on its own.
  test("matching ignores case and surrounding space", () => {
    expect(isReservedHandle("PRIVACY")).toBe(true);
    expect(isReservedHandle("  terms  ")).toBe(true);
  });
});
