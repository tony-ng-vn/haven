/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

// Insert a user row and return an authenticated test context bound to it.
// getAuthUserId reads identity.subject (split on "|"); a bare user id works.
async function asNewUser(t: ReturnType<typeof convexTest>) {
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {}));
  return { userId, as: t.withIdentity({ subject: userId }) };
}

test("addPerson creates a person owned by the caller with a timestamp", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);

  const id = await as.mutation(api.people.addPerson, { name: "Maya Chen" });

  const person = await t.run((ctx) => ctx.db.get("people", id));
  expect(person?.name).toBe("Maya Chen");
  expect(person?.userId).toBe(userId);
  expect(typeof person?.updatedAt).toBe("number");
});

test("addPerson rejects a blank name", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await expect(
    as.mutation(api.people.addPerson, { name: "   " }),
  ).rejects.toThrow("Name is required");
});

test("addPerson rejects an unauthenticated caller", async () => {
  const t = convexTest(schema, modules);
  await expect(
    t.mutation(api.people.addPerson, { name: "Maya" }),
  ).rejects.toThrow("Not signed in");
});

test("searchPeople matches the caller's people by name and excludes others", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  await me.as.mutation(api.people.addPerson, { name: "Maya Chen" });
  await me.as.mutation(api.people.addPerson, { name: "Felix Ng" });
  await other.as.mutation(api.people.addPerson, { name: "Maya Rao" });

  const results = await me.as.query(api.people.searchPeople, { query: "Maya" });
  expect(results.map((p) => p.name)).toEqual(["Maya Chen"]);
});

test("searchPeople with an empty query returns only the caller's recent people", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  await me.as.mutation(api.people.addPerson, { name: "Maya Chen" });
  await me.as.mutation(api.people.addPerson, { name: "Felix Ng" });
  // Another user's person must never appear in my empty-query results.
  await other.as.mutation(api.people.addPerson, { name: "Rao" });

  const results = await me.as.query(api.people.searchPeople, { query: "  " });
  expect(results.map((p) => p.name).sort()).toEqual(["Felix Ng", "Maya Chen"]);
});

test("getPerson returns the caller's person and null for another user's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  const myId = await me.as.mutation(api.people.addPerson, { name: "Maya" });
  const otherId = await other.as.mutation(api.people.addPerson, {
    name: "Rao",
  });

  expect((await me.as.query(api.people.getPerson, { id: myId }))?.name).toBe(
    "Maya",
  );
  expect(await me.as.query(api.people.getPerson, { id: otherId })).toBeNull();
});

test("updatePerson saves link and context and bumps updatedAt", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const id = await me.as.mutation(api.people.addPerson, { name: "Maya" });
  const before = await t.run((ctx) => ctx.db.get(id));

  await me.as.mutation(api.people.updatePerson, {
    id,
    link: "https://example.com",
    context: "recruiting agents at Photon",
  });

  const after = await t.run((ctx) => ctx.db.get(id));
  expect(after?.link).toBe("https://example.com");
  expect(after?.context).toBe("recruiting agents at Photon");
  expect(after!.updatedAt).toBeGreaterThanOrEqual(before!.updatedAt);
});

test("updatePerson rejects updating another user's person", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const otherId = await other.as.mutation(api.people.addPerson, {
    name: "Rao",
  });

  await expect(
    me.as.mutation(api.people.updatePerson, { id: otherId, context: "x" }),
  ).rejects.toThrow("Person not found");
});
