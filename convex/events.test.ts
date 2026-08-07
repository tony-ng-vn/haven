/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

let nextSubject = 0;
function asNewUser(t: ReturnType<typeof convexTest>) {
  const subject = `event_user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  const userId = `${issuer}|${subject}`;
  return { userId, as: t.withIdentity({ subject, issuer }) };
}

async function addPerson(
  as: ReturnType<ReturnType<typeof convexTest>["withIdentity"]>,
  handle: string,
) {
  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Maya Chen",
    context: "Met tonight",
    contactHandles: [{ platform: "instagram", value: handle }],
  });
  if (result.status !== "created") {
    throw new Error(`Expected a new person, got ${result.status}`);
  }
  return result.personId;
}

test("upsert keeps one event per user and client key", async () => {
  const t = convexTest(schema, modules);
  const { as } = asNewUser(t);

  const first = await as.mutation(api.events.upsert, {
    clientKey: "event-1",
    title: "Design meetup",
    startedAt: 1_000,
  });
  const ended = await as.mutation(api.events.upsert, {
    clientKey: "event-1",
    title: "Design meetup",
    startedAt: 1_000,
    endedAt: 2_000,
  });

  expect(first.status).toBe("created");
  expect(ended).toEqual({ status: "updated", eventId: first.eventId });
  expect(
    await as.mutation(api.events.upsert, {
      clientKey: "event-1",
      title: "Design meetup",
      startedAt: 1_000,
      endedAt: 2_000,
    }),
  ).toEqual({ status: "already", eventId: first.eventId });
});

test("a selected Apple Calendar event keeps its durable source snapshot", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = asNewUser(t);
  const created = await as.mutation(api.events.upsert, {
    clientKey: "apple-event-1",
    title: "Founders dinner",
    startedAt: 1_200,
    sourceProvider: "appleCalendar",
    sourceEventId: "calendar-item-42",
    sourceStartedAt: 1_000,
    sourceEndedAt: 2_000,
  });

  const saved = await t.run((ctx) => ctx.db.get("events", created.eventId));

  expect(saved).toMatchObject({
    userId,
    sourceProvider: "appleCalendar",
    sourceEventId: "calendar-item-42",
    sourceStartedAt: 1_000,
    sourceEndedAt: 2_000,
  });
});

test("a partial Apple Calendar source snapshot is rejected", async () => {
  const t = convexTest(schema, modules);
  const { as } = asNewUser(t);

  await expect(
    as.mutation(api.events.upsert, {
      clientKey: "apple-event-partial",
      title: "Founders dinner",
      startedAt: 1_200,
      sourceProvider: "appleCalendar",
      sourceEventId: "calendar-item-42",
    }),
  ).rejects.toThrow("Calendar event source is incomplete");
});

test("a delayed start cannot reopen or shorten an ended event", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = asNewUser(t);

  await as.mutation(api.events.upsert, {
    clientKey: "event-ended",
    title: "Demo night",
    startedAt: 1_000,
    endedAt: 3_000,
  });
  expect(
    await as.mutation(api.events.upsert, {
      clientKey: "event-ended",
      title: "Demo night",
      startedAt: 1_000,
    }),
  ).toMatchObject({ status: "already" });
  expect(
    await as.mutation(api.events.upsert, {
      clientKey: "event-ended",
      title: "Demo night",
      startedAt: 1_000,
      endedAt: 2_000,
    }),
  ).toMatchObject({ status: "already" });

  const saved = await t.run((ctx) =>
    ctx.db
      .query("events")
      .withIndex("by_userId_and_clientKey", (q) =>
        q.eq("userId", userId).eq("clientKey", "event-ended"),
      )
      .unique(),
  );
  expect(saved?.endedAt).toBe(3_000);
});

test("linkPerson creates a missing event and never duplicates the relation", async () => {
  const t = convexTest(schema, modules);
  const { as } = asNewUser(t);
  const personId = await addPerson(as, "maya.events");
  const event = {
    clientKey: "event-2",
    title: "Founders dinner",
    startedAt: 3_000,
  };

  const linked = await as.mutation(api.events.linkPerson, {
    ...event,
    personId,
  });
  const again = await as.mutation(api.events.linkPerson, {
    ...event,
    personId,
  });

  expect(linked.status).toBe("linked");
  expect(again).toEqual({ status: "already", eventId: linked.eventId });
  expect(await as.query(api.events.listForPerson, { personId })).toEqual([
    {
      _id: linked.eventId,
      title: "Founders dinner",
      startedAt: 3_000,
      endedAt: undefined,
    },
  ]);
});

test("events and person links stay private to their owner", async () => {
  const t = convexTest(schema, modules);
  const mine = asNewUser(t);
  const theirs = asNewUser(t);
  const personId = await addPerson(mine.as, "private.event");

  await expect(
    theirs.as.mutation(api.events.linkPerson, {
      clientKey: "event-3",
      title: "Private dinner",
      startedAt: 4_000,
      personId,
    }),
  ).rejects.toThrow("Person not found");
  await expect(
    theirs.as.query(api.events.listForPerson, { personId }),
  ).rejects.toThrow("Person not found");
});

test("event fields are trimmed and bounded", async () => {
  const t = convexTest(schema, modules);
  const { as } = asNewUser(t);

  const created = await as.mutation(api.events.upsert, {
    clientKey: " event-4 ",
    title: "  Community night  ",
    startedAt: 5_000,
  });
  expect(created.status).toBe("created");

  await expect(
    as.mutation(api.events.upsert, {
      clientKey: "event-5",
      title: "   ",
      startedAt: 5_000,
    }),
  ).rejects.toThrow("Event name is required");
  await expect(
    as.mutation(api.events.upsert, {
      clientKey: "event-6",
      title: "A".repeat(201),
      startedAt: 5_000,
    }),
  ).rejects.toThrow("Event name is too long");
});

test("listForPerson keeps the newest one hundred links", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = asNewUser(t);
  const personId = await addPerson(as, "many.events");

  await t.run(async (ctx) => {
    for (let index = 0; index < 101; index += 1) {
      const eventId = await ctx.db.insert("events", {
        userId,
        clientKey: `event-${index}`,
        title: `Event ${index}`,
        startedAt: index,
        updatedAt: index,
      });
      await ctx.db.insert("eventPeople", {
        userId,
        eventId,
        personId,
        eventStartedAt: index,
        linkedAt: 101 - index,
      });
    }
  });

  const listed = await as.query(api.events.listForPerson, { personId });
  expect(listed).toHaveLength(100);
  expect(listed[0].title).toBe("Event 100");
  expect(listed[listed.length - 1]?.title).toBe("Event 1");
});
