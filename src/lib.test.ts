import { describe, expect, test } from "vitest";
import { formatMonthYear, mapAuthError, normalizeUrl } from "./lib";

describe("mapAuthError", () => {
  test("wrong password reads as a calm mismatch message", () => {
    const error = new Error(
      "[CONVEX A(auth:signIn)] [Request ID: abc] Server Error Uncaught Error: InvalidSecret",
    );
    expect(mapAuthError(error, "signIn")).toBe(
      "That email and password do not match.",
    );
  });

  test("unknown account on sign-in uses the same non-revealing message", () => {
    const error = new Error("Uncaught Error: InvalidAccountId");
    expect(mapAuthError(error, "signIn")).toBe(
      "That email and password do not match.",
    );
  });

  test("existing account on sign-up points at signing in", () => {
    const error = new Error("Uncaught Error: Account alice already exists");
    expect(mapAuthError(error, "signUp")).toBe(
      "An account with that email already exists. Try signing in instead.",
    );
  });

  test("short password on sign-up explains the requirement", () => {
    const error = new Error("Uncaught Error: Invalid password");
    expect(mapAuthError(error, "signUp")).toBe(
      "Passwords need at least 8 characters.",
    );
  });

  test("network failure asks to retry", () => {
    const error = new TypeError("Failed to fetch");
    expect(mapAuthError(error, "signIn")).toBe(
      "Could not reach the server. Check your connection and try again.",
    );
  });

  test("anything unrecognized falls back to a generic retry line", () => {
    expect(mapAuthError(new Error("kaboom"), "signIn")).toBe(
      "Something went wrong. Please try again.",
    );
    expect(mapAuthError(undefined, "signUp")).toBe(
      "Something went wrong. Please try again.",
    );
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
