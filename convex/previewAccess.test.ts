/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import rateLimiterTest from "@convex-dev/rate-limiter/test";

const modules = import.meta.glob("./**/*.ts");

function newHarness() {
  const t = convexTest(schema, modules);
  rateLimiterTest.register(t);
  return t;
}

function asUser(t: ReturnType<typeof convexTest>, subject: string) {
  return t.withIdentity({
    subject,
    issuer: "https://test.clerk.accounts.dev",
  });
}

beforeEach(() => {
  vi.stubEnv("HAVEN_PREVIEW_CODE", "test-preview-code");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

test("the public check accepts only the configured preview code", async () => {
  const t = newHarness();

  await expect(
    t.mutation(api.previewAccess.checkCode, { code: "wrong-code" }),
  ).resolves.toEqual({ status: "invalid" });
  await expect(
    t.mutation(api.previewAccess.checkCode, { code: " test-preview-code " }),
  ).resolves.toEqual({ status: "valid" });
});

test("redeeming a valid code grants only the signed-in account", async () => {
  const t = newHarness();
  const invited = asUser(t, "invited");
  const stranger = asUser(t, "stranger");

  await expect(
    invited.mutation(api.previewAccess.redeemCode, {
      code: "test-preview-code",
    }),
  ).resolves.toEqual({ status: "granted" });

  await expect(
    invited.query(api.previewAccess.hasAccess, {}),
  ).resolves.toBe(true);
  await expect(
    stranger.query(api.previewAccess.hasAccess, {}),
  ).resolves.toBe(false);
});

test("redeeming is idempotent and an invalid code grants nothing", async () => {
  const t = newHarness();
  const invited = asUser(t, "invited");
  const stranger = asUser(t, "stranger");

  await expect(
    stranger.mutation(api.previewAccess.redeemCode, { code: "wrong-code" }),
  ).resolves.toEqual({ status: "invalid" });
  await expect(
    stranger.query(api.previewAccess.hasAccess, {}),
  ).resolves.toBe(false);

  await invited.mutation(api.previewAccess.redeemCode, {
    code: "test-preview-code",
  });
  await expect(
    invited.mutation(api.previewAccess.redeemCode, {
      code: "test-preview-code",
    }),
  ).resolves.toEqual({ status: "already" });

  const grants = await t.run((ctx) => ctx.db.query("previewAccess").take(10));
  expect(grants).toHaveLength(1);
});

test("preview access requires a signed-in account", async () => {
  const t = newHarness();

  await expect(t.query(api.previewAccess.hasAccess, {})).rejects.toThrow(
    "Not signed in",
  );
  await expect(
    t.mutation(api.previewAccess.redeemCode, { code: "test-preview-code" }),
  ).rejects.toThrow("Not signed in");
});

test("a missing server code fails closed", async () => {
  vi.stubEnv("HAVEN_PREVIEW_CODE", "");
  const t = newHarness();

  await expect(
    t.mutation(api.previewAccess.checkCode, { code: "test-preview-code" }),
  ).rejects.toThrow("Preview access is temporarily unavailable");
});

test("public code checks stop at the shared minute cap", async () => {
  const t = newHarness();

  for (let attempt = 0; attempt < 120; attempt += 1) {
    await t.mutation(api.previewAccess.checkCode, { code: "wrong-code" });
  }
  await expect(
    t.mutation(api.previewAccess.checkCode, { code: "wrong-code" }),
  ).rejects.toThrow("Too many requests");
});
