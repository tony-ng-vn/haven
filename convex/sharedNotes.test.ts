/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

let nextSubject = 0;
function asNewUser(t: ReturnType<typeof convexTest>) {
  const subject = `shared_user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  const userId = `${issuer}|${subject}`;
  return { userId, as: t.withIdentity({ subject, issuer }) };
}

// addPerson requires a handle and a note; these tests care about neither, so
// they spread this minimal valid payload first.
const manualAdd = {
  contactHandles: [{ platform: "phone", value: "unlisted" }],
  context: "met before this test",
};

test("connected users share one pair-scoped note", async () => {
  const t = convexTest(schema, modules);
  const ada = asNewUser(t);
  const ben = asNewUser(t);
  const adaPersonId = await ada.as.mutation(api.people.addPerson, {
    ...manualAdd,
    name: "Ben",
    context: "Private reminder",
  });
  const benPersonId = await ben.as.mutation(api.people.addPerson, {
    ...manualAdd,
    name: "Ada",
    context: "Ben's private reminder",
  });
  const connectionId = await t.run((ctx) =>
    ctx.db.insert("connections", {
      userAId: ada.userId,
      userBId: ben.userId,
      personAId: adaPersonId,
      personBId: benPersonId,
      status: "connected",
      createdAt: Date.now(),
      updatedAt: Date.now(),
    }),
  );

  await ada.as.mutation(api.sharedNotes.updateForPerson, {
    personId: adaPersonId,
    content: "We are comparing notes on the Lisbon trip.",
  });

  const fromAda = await ada.as.query(api.sharedNotes.getForPerson, {
    personId: adaPersonId,
  });
  const fromBen = await ben.as.query(api.sharedNotes.getForPerson, {
    personId: benPersonId,
  });
  expect(fromAda).toMatchObject({
    connectionId,
    content: "We are comparing notes on the Lisbon trip.",
    updatedByMe: true,
  });
  expect(fromBen).toMatchObject({
    connectionId,
    content: "We are comparing notes on the Lisbon trip.",
    updatedByMe: false,
  });
});

test("shared notes do not change either user's private context", async () => {
  const t = convexTest(schema, modules);
  const ada = asNewUser(t);
  const ben = asNewUser(t);
  const adaPersonId = await ada.as.mutation(api.people.addPerson, {
    ...manualAdd,
    name: "Ben",
    context: "Private to Ada",
  });
  const benPersonId = await ben.as.mutation(api.people.addPerson, {
    ...manualAdd,
    name: "Ada",
    context: "Private to Ben",
  });
  await t.run((ctx) =>
    ctx.db.insert("connections", {
      userAId: ada.userId,
      userBId: ben.userId,
      personAId: adaPersonId,
      personBId: benPersonId,
      status: "connected",
      createdAt: Date.now(),
      updatedAt: Date.now(),
    }),
  );

  await ben.as.mutation(api.sharedNotes.updateForPerson, {
    personId: benPersonId,
    content: "Shared between them",
  });

  const adaPerson = await ada.as.query(api.people.getPerson, { id: adaPersonId });
  const benPerson = await ben.as.query(api.people.getPerson, { id: benPersonId });
  expect(adaPerson?.context).toBe("Private to Ada");
  expect(benPerson?.context).toBe("Private to Ben");
});

test("unconnected people cannot read or write shared notes", async () => {
  const t = convexTest(schema, modules);
  const ada = asNewUser(t);
  const adaPersonId = await ada.as.mutation(api.people.addPerson, {
    ...manualAdd,
    name: "Ben",
  });

  await expect(
    ada.as.query(api.sharedNotes.getForPerson, { personId: adaPersonId }),
  ).resolves.toBeNull();
  await expect(
    ada.as.mutation(api.sharedNotes.updateForPerson, {
      personId: adaPersonId,
      content: "No mutual link yet",
    }),
  ).rejects.toThrow("Mutual connection not found");
});

test("shared note writes reject another user's person row", async () => {
  const t = convexTest(schema, modules);
  const ada = asNewUser(t);
  const ben = asNewUser(t);
  const benPersonId = await ben.as.mutation(api.people.addPerson, {
    ...manualAdd,
    name: "Ada",
  });

  await expect(
    ada.as.mutation(api.sharedNotes.updateForPerson, {
      personId: benPersonId,
      content: "Trying to write through Ben's private row",
    }),
  ).rejects.toThrow("Mutual connection not found");
});

test("shared note updates are length-capped", async () => {
  const t = convexTest(schema, modules);
  const ada = asNewUser(t);
  const ben = asNewUser(t);
  const adaPersonId = await ada.as.mutation(api.people.addPerson, {
    ...manualAdd,
    name: "Ben",
  });
  const benPersonId = await ben.as.mutation(api.people.addPerson, {
    ...manualAdd,
    name: "Ada",
  });
  await t.run((ctx) =>
    ctx.db.insert("connections", {
      userAId: ada.userId,
      userBId: ben.userId,
      personAId: adaPersonId,
      personBId: benPersonId,
      status: "connected",
      createdAt: Date.now(),
      updatedAt: Date.now(),
    }),
  );

  await expect(
    ada.as.mutation(api.sharedNotes.updateForPerson, {
      personId: adaPersonId,
      content: "x".repeat(4001),
    }),
  ).rejects.toThrow("Shared note is too long -- keep it under 4000 characters");
});
