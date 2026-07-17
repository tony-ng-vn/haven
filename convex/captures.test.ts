/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

async function asNewUser(t: ReturnType<typeof convexTest>) {
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {}));
  return { userId, as: t.withIdentity({ subject: userId }) };
}

async function seedScreenshot(t: ReturnType<typeof convexTest>) {
  return await t.run(async (ctx) =>
    ctx.storage.store(new Blob(["fake-image"], { type: "image/png" })),
  );
}

const EXTRACTION = {
  is_profile: true,
  platform: "x",
  name: "Ada Lovelace",
  handle: "@ada_l",
  headline: "Compiler engineer",
  bio: "Building symbolic math tools.",
};

// A deterministic 1536-dim unit vector with a 1 at the given position.
function unitVector(hotIndex: number): number[] {
  const vector = new Array(1536).fill(0);
  vector[hotIndex] = 1;
  return vector;
}

// Stub the two OpenAI endpoints. Storage URLs (and anything else) fall
// through to the real fetch so convex-test internals keep working.
function stubOpenAI(options: {
  extraction?: unknown;
  embedding?: number[];
  failExtraction?: boolean;
}) {
  const realFetch = globalThis.fetch;
  vi.stubGlobal(
    "fetch",
    async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.includes("api.openai.com/v1/chat/completions")) {
        if (options.failExtraction) {
          return new Response("upstream error", { status: 500 });
        }
        return Response.json({
          choices: [
            { message: { content: JSON.stringify(options.extraction) } },
          ],
        });
      }
      if (url.includes("api.openai.com/v1/embeddings")) {
        return Response.json({
          data: [{ embedding: options.embedding ?? unitVector(0) }],
        });
      }
      return realFetch(input, init);
    },
  );
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

test("createCapture extracts a profile in the background", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("ready");
  expect(capture?.extracted).toMatchObject({
    platform: "x",
    name: "Ada Lovelace",
    handle: "@ada_l",
  });
});

test("a screenshot that is not a profile fails calmly", async () => {
  stubOpenAI({ extraction: { ...EXTRACTION, is_profile: false } });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("failed");
  expect(capture?.error).toBe("Could not read a profile in this screenshot");
});

test("an upstream failure marks the capture failed, not stuck pending", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("failed");
});

test("listCaptures returns only the caller's captures, with image urls", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  await me.as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await other.as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const mine = await me.as.query(api.captures.listCaptures, {});
  expect(mine).toHaveLength(1);
  expect(typeof mine[0].imageUrl).toBe("string");
});

test("acceptCapture creates an owned person and consumes the capture", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await as.mutation(api.captures.acceptCapture, {
    captureId,
    link: "https://x.com/ada_l",
    context: "Met at the meetup.",
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person).toMatchObject({
    userId,
    name: "Ada Lovelace",
    link: "https://x.com/ada_l",
    context: "Met at the meetup.",
    platform: "x",
    handle: "@ada_l",
    screenshotId,
  });
  // Embedding was computed in the background from the person's text.
  expect(person?.embedding).toHaveLength(1536);
  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).toBeNull();
});

test("another user cannot accept or discard my capture", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const captureId = await me.as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    other.as.mutation(api.captures.acceptCapture, { captureId }),
  ).rejects.toThrow("Capture not found");
  await expect(
    other.as.mutation(api.captures.discardCapture, { captureId }),
  ).rejects.toThrow("Capture not found");
});

test("discardCapture removes the capture and its file", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await as.mutation(api.captures.discardCapture, { captureId });

  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).toBeNull();
  expect(
    await t.run((ctx) => ctx.storage.getUrl(screenshotId)),
  ).toBeNull();
});

test("semanticSearch finds my people by meaning and never another user's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  // Seed embeddings directly: person A matches the query vector exactly,
  // person B is orthogonal (filtered by score), and the other user's person
  // shares A's vector but must be excluded by the userId filter.
  await t.run(async (ctx) => {
    await ctx.db.insert("people", {
      userId: me.userId,
      name: "Ada Lovelace",
      context: "Compiler engineer from the meetup",
      updatedAt: 1,
      embedding: unitVector(0),
      embeddedText: "a",
    });
    await ctx.db.insert("people", {
      userId: me.userId,
      name: "Grace Hopper",
      updatedAt: 1,
      embedding: unitVector(1),
      embeddedText: "b",
    });
    await ctx.db.insert("people", {
      userId: other.userId,
      name: "Impostor",
      updatedAt: 1,
      embedding: unitVector(0),
      embeddedText: "c",
    });
  });

  stubOpenAI({ embedding: unitVector(0) });
  const results = await me.as.action(api.people.semanticSearch, {
    query: "who was the compiler person",
  });

  expect(results.map((r) => r.name)).toEqual(["Ada Lovelace"]);
  expect(results[0].score).toBeGreaterThan(0.9);
});

test("updatePerson refreshes the embedding from the new context", async () => {
  stubOpenAI({ embedding: unitVector(2) });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const personId = await as.mutation(api.people.addPerson, { name: "Maya" });
  await as.mutation(api.people.updatePerson, {
    id: personId,
    context: "Runs the observatory",
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.embedding).toHaveLength(1536);
  expect(person?.embeddedText).toBe("Maya\nRuns the observatory");
});
