/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import { MAX_JOINS_PER_MINUTE } from "./waitlist";

const modules = import.meta.glob("./**/*.ts");

test("joinWaitlist stores a trimmed name and normalized email, and reports joined", async () => {
  const t = convexTest(schema, modules);

  const result = await t.mutation(api.waitlist.joinWaitlist, {
    name: "  Ada Lovelace  ",
    email: "  Tony@Example.COM ",
    source: "desktop",
  });
  expect(result).toEqual({ status: "joined" });

  const rows = await t.run((ctx) => ctx.db.query("waitlist").collect());
  expect(rows).toHaveLength(1);
  expect(rows[0].name).toBe("Ada Lovelace");
  expect(rows[0].email).toBe("tony@example.com");
  expect(rows[0].source).toBe("desktop");
});

test("a new join schedules exactly one confirmation email", async () => {
  const t = convexTest(schema, modules);

  await t.mutation(api.waitlist.joinWaitlist, {
    name: "Ada",
    email: "a@b.com",
    source: "desktop",
  });

  const scheduled = await t.run((ctx) =>
    ctx.db.system.query("_scheduled_functions").collect(),
  );
  expect(scheduled).toHaveLength(1);
  expect(scheduled[0].name).toContain("sendConfirmationEmail");

  // With no RESEND_API_KEY set the action must run to completion as a no-op,
  // never throwing -- a missing provider can't break the join flow.
  await t.finishInProgressScheduledFunctions();
});

test("joining the same address again is idempotent and does not re-email", async () => {
  const t = convexTest(schema, modules);

  await t.mutation(api.waitlist.joinWaitlist, {
    name: "Ada",
    email: "a@b.com",
    source: "phone",
  });
  const again = await t.mutation(api.waitlist.joinWaitlist, {
    name: "Impostor",
    email: "A@B.com",
    source: "desktop",
  });

  expect(again).toEqual({ status: "already" });
  const rows = await t.run((ctx) => ctx.db.query("waitlist").collect());
  expect(rows).toHaveLength(1);
  // A re-join must not overwrite the name or source captured the first time.
  expect(rows[0].name).toBe("Ada");
  expect(rows[0].source).toBe("phone");

  // Only the first join scheduled a confirmation; the "already" path emails no one.
  const scheduled = await t.run((ctx) =>
    ctx.db.system.query("_scheduled_functions").collect(),
  );
  expect(scheduled).toHaveLength(1);
});

test("an invalid email is rejected and stores nothing", async () => {
  const t = convexTest(schema, modules);

  await expect(
    t.mutation(api.waitlist.joinWaitlist, {
      name: "Ada",
      email: "not-an-email",
      source: "desktop",
    }),
  ).rejects.toThrow();

  const rows = await t.run((ctx) => ctx.db.query("waitlist").collect());
  expect(rows).toHaveLength(0);
});

test("a blank or whitespace-only name is rejected and stores nothing", async () => {
  const t = convexTest(schema, modules);

  await expect(
    t.mutation(api.waitlist.joinWaitlist, {
      name: "   ",
      email: "ada@example.com",
      source: "desktop",
    }),
  ).rejects.toThrow();

  const rows = await t.run((ctx) => ctx.db.query("waitlist").collect());
  expect(rows).toHaveLength(0);
});

test("a flood is capped by the global per-minute rate limit", async () => {
  const t = convexTest(schema, modules);

  // Fill the window with distinct addresses so dedupe never masks the cap.
  for (let i = 0; i < MAX_JOINS_PER_MINUTE; i++) {
    await t.mutation(api.waitlist.joinWaitlist, {
      name: "Flood Tester",
      email: `flood${i}@example.com`,
      source: "desktop",
    });
  }

  await expect(
    t.mutation(api.waitlist.joinWaitlist, {
      name: "One Too Many",
      email: "one-too-many@example.com",
      source: "desktop",
    }),
  ).rejects.toThrow();
});
