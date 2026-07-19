/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import schema from "./schema";
import { checkRateLimit } from "./rateLimit";

const modules = import.meta.glob("./**/*.ts");

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

test("admits up to max calls in a window, then throws on the N+1th", async () => {
  const t = convexTest(schema, modules);
  await t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000));
  await t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000));
  await expect(
    t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000)),
  ).rejects.toThrow("Too many requests -- please wait a moment");
});

test("a new window admits again after the old one expires", async () => {
  const t = convexTest(schema, modules);
  await t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000));
  await t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000));
  await expect(
    t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000)),
  ).rejects.toThrow("Too many requests -- please wait a moment");

  vi.setSystemTime(Date.now() + 60_000);

  await expect(
    t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000)),
  ).resolves.toBeNull();
});

test("limits are tracked per user, not shared globally", async () => {
  const t = convexTest(schema, modules);
  await t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000));
  await t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000));
  await expect(
    t.run((ctx) => checkRateLimit(ctx, "user_a", "test", 2, 60_000)),
  ).rejects.toThrow("Too many requests -- please wait a moment");

  // user_b's spend is untouched by user_a exhausting their window.
  await expect(
    t.run((ctx) => checkRateLimit(ctx, "user_b", "test", 2, 60_000)),
  ).resolves.toBeNull();
});

test("limits are tracked per action, not shared across actions for the same user", async () => {
  const t = convexTest(schema, modules);
  await t.run((ctx) => checkRateLimit(ctx, "user_a", "actionOne", 1, 60_000));
  await expect(
    t.run((ctx) => checkRateLimit(ctx, "user_a", "actionOne", 1, 60_000)),
  ).rejects.toThrow("Too many requests -- please wait a moment");

  // A different action name for the same user gets its own window.
  await expect(
    t.run((ctx) => checkRateLimit(ctx, "user_a", "actionTwo", 1, 60_000)),
  ).resolves.toBeNull();
});
