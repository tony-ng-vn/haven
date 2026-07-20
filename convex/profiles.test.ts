/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

let nextSubject = 0;
function asNewUser(t: ReturnType<typeof convexTest>) {
  const subject = `profile_user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  const userId = `${issuer}|${subject}`;
  return { userId, as: t.withIdentity({ subject, issuer }) };
}

test("setUsername claims a normalized username owned by the caller", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  const profile = await me.as.mutation(api.profiles.setUsername, {
    username: "  @Maya_7 ",
  });

  expect(profile.username).toBe("maya_7");
  expect(await me.as.query(api.profiles.getMyProfile, {})).toMatchObject({
    username: "maya_7",
  });
  const stored = await t.run((ctx) =>
    ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", me.userId))
      .unique(),
  );
  expect(stored?.username).toBe("maya_7");
});

test("setUsername enforces uniqueness across users", async () => {
  const t = convexTest(schema, modules);
  const maya = asNewUser(t);
  const other = asNewUser(t);

  await maya.as.mutation(api.profiles.setUsername, { username: "maya" });

  await expect(
    other.as.mutation(api.profiles.setUsername, { username: "MAYA" }),
  ).rejects.toThrow("That username is already taken");
});

test("profile functions reject unauthenticated callers", async () => {
  const t = convexTest(schema, modules);

  await expect(t.query(api.profiles.getMyProfile, {})).rejects.toThrow(
    "Not signed in",
  );
  await expect(
    t.mutation(api.profiles.setUsername, { username: "maya" }),
  ).rejects.toThrow("Not signed in");
  await expect(
    t.query(api.profiles.lookupByUsername, { username: "maya" }),
  ).rejects.toThrow("Not signed in");
  await expect(
    t.mutation(api.profiles.meetExchange, { username: "maya" }),
  ).rejects.toThrow("Not signed in");
});

test("lookupByUsername returns only public username data", async () => {
  const t = convexTest(schema, modules);
  const maya = asNewUser(t);
  const viewer = asNewUser(t);
  await maya.as.mutation(api.profiles.setUsername, { username: "maya" });

  const found = await viewer.as.query(api.profiles.lookupByUsername, {
    username: "@MAYA",
  });

  expect(found).toEqual({ username: "maya" });
});

test("meetExchange creates private people rows for both sides", async () => {
  const t = convexTest(schema, modules);
  const alice = asNewUser(t);
  const bob = asNewUser(t);
  await alice.as.mutation(api.profiles.setUsername, { username: "alice" });
  await bob.as.mutation(api.profiles.setUsername, { username: "bob" });

  const exchanged = await alice.as.mutation(api.profiles.meetExchange, {
    username: "@bob",
  });

  expect(exchanged.peerUsername).toBe("bob");

  const alicePeople = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", alice.userId))
      .collect(),
  );
  const bobPeople = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", bob.userId))
      .collect(),
  );
  expect(alicePeople).toHaveLength(1);
  expect(bobPeople).toHaveLength(1);
  expect(alicePeople[0]).toMatchObject({
    _id: exchanged.personId,
    name: "@bob",
    userId: alice.userId,
    eunoContactUserId: bob.userId,
    platform: "Euno",
    handle: "bob",
  });
  expect(bobPeople[0]).toMatchObject({
    name: "@alice",
    userId: bob.userId,
    eunoContactUserId: alice.userId,
    platform: "Euno",
    handle: "alice",
  });

  const connection = await t.run((ctx) =>
    ctx.db
      .query("connections")
      .withIndex("by_userAId_and_userBId", (q) => {
        const [a, b] =
          alice.userId < bob.userId
            ? [alice.userId, bob.userId]
            : [bob.userId, alice.userId];
        return q.eq("userAId", a).eq("userBId", b);
      })
      .unique(),
  );
  expect(connection).toMatchObject({ status: "connected" });

  const sharedFromAlice = await alice.as.query(api.sharedNotes.getForPerson, {
    personId: exchanged.personId,
  });
  expect(sharedFromAlice).not.toBeNull();
  expect(sharedFromAlice?.connectionId).toBe(connection?._id);

  expect(
    (await alice.as.query(api.people.searchPeople, { query: "bob" })).map(
      (p) => p.name,
    ),
  ).toEqual(["@bob"]);
  expect(
    (await bob.as.query(api.people.searchPeople, { query: "alice" })).map(
      (p) => p.name,
    ),
  ).toEqual(["@alice"]);
});

test("meetExchange is idempotent for repeated in-person confirmations", async () => {
  const t = convexTest(schema, modules);
  const alice = asNewUser(t);
  const bob = asNewUser(t);
  await alice.as.mutation(api.profiles.setUsername, { username: "alice" });
  await bob.as.mutation(api.profiles.setUsername, { username: "bob" });

  const first = await alice.as.mutation(api.profiles.meetExchange, {
    username: "bob",
  });
  const second = await alice.as.mutation(api.profiles.meetExchange, {
    username: "bob",
  });

  expect(second.personId).toBe(first.personId);
  const counts = await t.run(async (ctx) => ({
    alice: await ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", alice.userId))
      .collect(),
    bob: await ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", bob.userId))
      .collect(),
  }));
  expect(counts.alice).toHaveLength(1);
  expect(counts.bob).toHaveLength(1);
  const connections = await t.run((ctx) =>
    ctx.db.query("connections").collect(),
  );
  expect(connections).toHaveLength(1);
});

test("meetExchange requires a username for self and rejects self exchange", async () => {
  const t = convexTest(schema, modules);
  const alice = asNewUser(t);

  await expect(
    alice.as.mutation(api.profiles.meetExchange, { username: "bob" }),
  ).rejects.toThrow("Choose your Euno username first");

  await alice.as.mutation(api.profiles.setUsername, { username: "alice" });
  await expect(
    alice.as.mutation(api.profiles.meetExchange, { username: "alice" }),
  ).rejects.toThrow("Enter the other person's username");
});
