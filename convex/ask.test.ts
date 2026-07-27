/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import schema from "./schema";
import { ASK_FIXTURES } from "../src/askFixtures";

const modules = import.meta.glob("./**/*.ts");

function newHarness() {
  return convexTest(schema, modules);
}
type Harness = ReturnType<typeof newHarness>;

let nextSubject = 0;
function asNewUser(t: Harness) {
  const subject = `ask_user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  const userId = `${issuer}|${subject}`;
  return { userId, as: t.withIdentity({ subject, issuer }) };
}

function unitVector(hotIndex: number): number[] {
  const vector = new Array(1536).fill(0);
  vector[hotIndex] = 1;
  return vector;
}

type AskAnswer = {
  matches: Array<{ ref: number; kind: string; why: string }>;
  clarifying_question: string | null;
};

// Records the network listing every ask sends, and replies with whatever the
// test wants the model to have said. Embeddings fall through to a fixed
// vector so the narrowing path can run.
function stubProvider(answer: AskAnswer | ((prompt: string) => AskAnswer)) {
  const prompts: string[] = [];
  vi.stubGlobal(
    "fetch",
    async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.includes("/embeddings")) {
        return Response.json({ data: [{ embedding: unitVector(0) }] });
      }
      const body = JSON.parse(String(init?.body)) as {
        messages: Array<{ content: string }>;
      };
      const listing = body.messages[1].content;
      prompts.push(listing);
      const reply = typeof answer === "function" ? answer(listing) : answer;
      return Response.json({
        choices: [{ message: { content: JSON.stringify(reply) } }],
      });
    },
  );
  return {
    prompts,
    lastPrompt: () => prompts[prompts.length - 1] ?? "",
    callCount: () => prompts.length,
  };
}

beforeEach(() => {
  vi.stubEnv("OPENAI_API_KEY", "sk-test");
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

// A person plus one memory line, inserted directly so a test can control the
// text and the vector without going through the write paths.
//
// Everything is embedded by default, which is both what production looks like
// (every write path schedules an embed) and what convex-test needs: its
// vectorSearch scores every row in the table and throws on one that has no
// vector, where real Convex simply leaves it out of the index.
async function seedPerson(
  t: Harness,
  userId: string,
  fields: {
    name: string;
    note?: string;
    company?: string;
    role?: string;
    embedding?: number[];
    memoryEmbedding?: number[];
    updatedAt?: number;
  },
): Promise<Id<"people">> {
  // Orthogonal to the query vector the stub returns, so a person only ranks
  // above another when a test says so.
  const embedding = fields.embedding ?? unitVector(1000);
  const memoryEmbedding = fields.memoryEmbedding ?? unitVector(1001);
  return await t.run(async (ctx) => {
    const personId = await ctx.db.insert("people", {
      userId,
      name: fields.name,
      company: fields.company,
      role: fields.role,
      updatedAt: fields.updatedAt ?? 1,
      embedding,
      embeddedText: fields.name,
    });
    if (fields.note !== undefined) {
      await ctx.db.insert("memories", {
        userId,
        personId,
        text: fields.note,
        createdAt: 1_750_000_000_000,
        embedding: memoryEmbedding,
        embeddedText: fields.note,
      });
    }
    return personId;
  });
}

// ----------------------------------------------------------- the contract

test("ask answers with the people behind the refs the model named", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  const ada = await seedPerson(t, userId, {
    name: "Ada Lovelace",
    note: "works on an infinite-context-window database",
    updatedAt: 2,
  });
  const alan = await seedPerson(t, userId, {
    name: "Alan Turing",
    company: "Y Combinator",
    role: "Analyst",
    updatedAt: 1,
  });
  const provider = stubProvider({
    matches: [
      { ref: 1, kind: "direct", why: "you wrote that they work on a database" },
      { ref: 2, kind: "bridge", why: "screens YC applications" },
    ],
    clarifying_question: null,
  });

  const result = await as.action(api.people.ask, {
    query: "anyone with database experience",
  });

  expect(result.matches).toEqual([
    {
      personId: ada,
      kind: "direct",
      why: "you wrote that they work on a database",
    },
    { personId: alan, kind: "bridge", why: "screens YC applications" },
  ]);
  expect(result.clarifyingQuestion).toBeNull();
  // Newest first, and the memory line rides along with its date.
  expect(provider.lastPrompt()).toContain("#1 Ada Lovelace");
  expect(provider.lastPrompt()).toContain(
    "- 2025-06-15: works on an infinite-context-window database",
  );
  expect(provider.lastPrompt()).toContain("#2 Alan Turing | Analyst at Y Combinator");
});

test("ask passes a clarifying question through instead of guessing", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedPerson(t, userId, { name: "Ada Lovelace" });
  stubProvider({
    matches: [],
    clarifying_question: "What do you need them for?",
  });

  const result = await as.action(api.people.ask, { query: "who should I talk to" });

  expect(result.matches).toEqual([]);
  expect(result.clarifyingQuestion).toBe("What do you need them for?");
});

test("ask sends prior turns so a refinement keeps its context", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedPerson(t, userId, { name: "Ada Lovelace" });
  let sent: Array<{ role: string; content: string }> = [];
  vi.stubGlobal("fetch", async (_input: RequestInfo | URL, init?: RequestInit) => {
    sent = (JSON.parse(String(init?.body)) as {
      messages: Array<{ role: string; content: string }>;
    }).messages;
    return Response.json({
      choices: [
        {
          message: {
            content: JSON.stringify({ matches: [], clarifying_question: null }),
          },
        },
      ],
    });
  });

  await as.action(api.people.ask, {
    query: "for a backend role",
    history: [
      { role: "user", text: "who should I talk to" },
      { role: "assistant", text: "What do you need them for?" },
    ],
  });

  expect(sent.map((m) => m.role)).toEqual([
    "system",
    "user",
    "user",
    "assistant",
    "user",
  ]);
  // The live question comes last, after the history it refines.
  expect(sent[sent.length - 1].content).toBe("for a backend role");
});

// -------------------------------------------------- guarding the contract

test("ask drops refs the model was never shown", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  const ada = await seedPerson(t, userId, { name: "Ada Lovelace" });
  stubProvider({
    matches: [
      { ref: 99, kind: "direct", why: "invented" },
      { ref: 0, kind: "direct", why: "off by one" },
      { ref: 1, kind: "direct", why: "real" },
    ],
    clarifying_question: null,
  });

  const result = await as.action(api.people.ask, { query: "anyone" });

  expect(result.matches).toEqual([
    { personId: ada, kind: "direct", why: "real" },
  ]);
});

test("ask keeps one match per person and drops kinds outside the schema", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  const ada = await seedPerson(t, userId, { name: "Ada Lovelace" });
  await seedPerson(t, userId, { name: "Grace Hopper", updatedAt: 0 });
  stubProvider({
    matches: [
      { ref: 1, kind: "direct", why: "first" },
      { ref: 1, kind: "bridge", why: "same person again" },
      { ref: 2, kind: "maybe", why: "not a kind we accept" },
    ],
    clarifying_question: null,
  });

  const result = await as.action(api.people.ask, { query: "anyone" });

  expect(result.matches).toEqual([
    { personId: ada, kind: "direct", why: "first" },
  ]);
});

test("ask caps how many people one answer can name", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  for (let i = 0; i < 15; i++) {
    await seedPerson(t, userId, { name: `Person ${i}`, updatedAt: 100 - i });
  }
  stubProvider({
    matches: Array.from({ length: 15 }, (_, i) => ({
      ref: i + 1,
      kind: "direct",
      why: "everyone",
    })),
    clarifying_question: null,
  });

  const result = await as.action(api.people.ask, { query: "anyone" });

  expect(result.matches).toHaveLength(10);
});

test("ask never shows one user's network to another", async () => {
  const t = newHarness();
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  await seedPerson(t, me.userId, { name: "Ada Lovelace" });
  await seedPerson(t, other.userId, { name: "Somebody Else's Contact" });
  const provider = stubProvider({ matches: [], clarifying_question: null });

  await me.as.action(api.people.ask, { query: "anyone" });

  expect(provider.lastPrompt()).toContain("Ada Lovelace");
  expect(provider.lastPrompt()).not.toContain("Somebody Else's Contact");
});

test("ask spends nothing when there is nobody to ask about", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const provider = stubProvider({ matches: [], clarifying_question: null });

  const result = await as.action(api.people.ask, { query: "anyone" });

  expect(result).toEqual({ matches: [], clarifyingQuestion: null });
  expect(provider.callCount()).toBe(0);
});

test("ask rejects an oversized question or history rather than trimming it", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedPerson(t, userId, { name: "Ada Lovelace" });
  const provider = stubProvider({ matches: [], clarifying_question: null });

  await expect(
    as.action(api.people.ask, { query: "x".repeat(2001) }),
  ).rejects.toThrow("2000 characters");
  await expect(
    as.action(api.people.ask, {
      query: "anyone",
      history: [{ role: "user", text: "x".repeat(2001) }],
    }),
  ).rejects.toThrow("2000 characters");
  await expect(
    as.action(api.people.ask, {
      query: "anyone",
      history: Array.from({ length: 21 }, () => ({
        role: "user" as const,
        text: "hi",
      })),
    }),
  ).rejects.toThrow("too long");
  await expect(as.action(api.people.ask, { query: "  " })).rejects.toThrow(
    "Ask a question",
  );
  expect(provider.callCount()).toBe(0);
});

test("ask is rate-limited per minute and per day", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedPerson(t, userId, { name: "Ada Lovelace" });
  stubProvider({ matches: [], clarifying_question: null });

  await as.action(api.people.ask, { query: "anyone" });

  const windows = await t.run((ctx) =>
    ctx.db
      .query("rateLimits")
      .withIndex("by_user_action", (q) => q.eq("userId", userId))
      .collect(),
  );
  expect(windows.map((w) => w.action).sort()).toEqual(["ask:day", "ask:minute"]);
});

// ------------------------------------------------------- the narrowing path

test("a network too large for one prompt is chosen by the question", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  // Four people whose notes together far exceed the prompt budget, so the
  // recency pass cannot fit them all and retrieval has to pick.
  const bulk = "x".repeat(60_000);
  await seedPerson(t, userId, {
    name: "Newest Person",
    note: bulk,
    updatedAt: 400,
    memoryEmbedding: unitVector(9),
  });
  await seedPerson(t, userId, {
    name: "Second Person",
    note: bulk,
    updatedAt: 300,
    memoryEmbedding: unitVector(9),
  });
  const wanted = await seedPerson(t, userId, {
    name: "Buried Match",
    note: "works on an infinite-context-window database",
    updatedAt: 1,
    // The stub embeds every query as unitVector(0), so this is the top hit.
    memoryEmbedding: unitVector(0),
  });
  const provider = stubProvider({
    matches: [{ ref: 1, kind: "direct", why: "the database note" }],
    clarifying_question: null,
  });

  const result = await as.action(api.people.ask, {
    query: "anyone with database experience",
  });

  // Retrieval reordered the network, so the buried person is now #1.
  expect(provider.lastPrompt()).toContain("#1 Buried Match");
  expect(result.matches).toEqual([
    { personId: wanted, kind: "direct", why: "the database note" },
  ]);
});

// ------------------------------------------------------------- the fixtures

test("every fixture network is well formed and its expectations are reachable", () => {
  expect(ASK_FIXTURES.length).toBeGreaterThan(0);
  for (const fixture of ASK_FIXTURES) {
    const refs = [...fixture.network.matchAll(/^#(\d+) /gm)].map((match) =>
      Number(match[1]),
    );
    // Refs are what the model answers with, so a gap or a repeat in a fixture
    // would make its recall number meaningless.
    expect(refs).toEqual(refs.map((_, index) => index + 1));
    expect(fixture.query.trim()).not.toBe("");
    for (const expected of fixture.expected) {
      expect(refs).toContain(expected.ref);
    }
    if (fixture.expectClarification === true) {
      expect(fixture.expected).toEqual([]);
    }
  }
});
