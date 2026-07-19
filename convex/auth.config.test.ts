import { afterEach, describe, expect, test, vi } from "vitest";

// process.env.CLERK_JWT_ISSUER_DOMAIN! used to silently resolve to
// `domain: undefined` when unset, which only ever surfaced as an opaque
// "not authenticated" failure at sign-in time. It must fail loudly here,
// at deploy/import time, instead.

const ENV_KEY = "CLERK_JWT_ISSUER_DOMAIN";
const original = process.env[ENV_KEY];

afterEach(() => {
  if (original === undefined) delete process.env[ENV_KEY];
  else process.env[ENV_KEY] = original;
  vi.resetModules();
});

describe("auth.config", () => {
  test("throws a descriptive error when CLERK_JWT_ISSUER_DOMAIN is unset", async () => {
    delete process.env[ENV_KEY];
    vi.resetModules();
    await expect(import("./auth.config")).rejects.toThrow(
      /CLERK_JWT_ISSUER_DOMAIN/,
    );
  });

  test("throws when the domain is set to an empty string", async () => {
    process.env[ENV_KEY] = "";
    vi.resetModules();
    await expect(import("./auth.config")).rejects.toThrow(
      /CLERK_JWT_ISSUER_DOMAIN/,
    );
  });

  test("builds the provider config when the domain is set", async () => {
    process.env[ENV_KEY] = "https://example.clerk.accounts.dev";
    vi.resetModules();
    const mod = await import("./auth.config");
    expect(mod.default.providers[0].domain).toBe(
      "https://example.clerk.accounts.dev",
    );
    expect(mod.default.providers[0].applicationID).toBe("convex");
  });
});
