import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";
import { WAITLIST_COPY } from "./waitlistCopy";

const waitlistSource = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), "Waitlist.tsx"),
  "utf8",
);

describe("waitlist copy", () => {
  test("is a single voice, not a desktop map and a phone map", () => {
    // Shape guard: if someone reintroduces Record<Mode, {...}>, this fails.
    expect(WAITLIST_COPY).toEqual({
      eyebrow: "Haven - private beta",
      headline: "Your people are a constellation.",
      sub: "We keep everyone you meet in one place, and help you find them again when you forget their name.",
      cta: "Join",
      submitting: "Joining",
      fine: "Private beta",
      joinedTitle: "You are on the list.",
      alreadyTitle: "You're already on the list.",
      joinedBody:
        "Thank you for joining us, to be in the true social that brings you to other people in your life",
      alreadyBody:
        "This email is already registered - no need to sign up again. We'll be in touch.",
    });
  });

  test("Waitlist.tsx does not keep a second per-mode copy table", () => {
    // The bug class: a COPY: Record<Mode, ...> next to the layout breakpoint.
    // Layout may still branch on mode; wording must not.
    expect(waitlistSource).toMatch(/WAITLIST_COPY/);
    expect(waitlistSource).not.toMatch(/Record<\s*Mode\s*,/);
    expect(waitlistSource).not.toMatch(/\bcta:\s*"Request access"/);
    expect(waitlistSource).not.toMatch(/The people you meet, never lost again/);
  });
});
