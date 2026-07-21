/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

test("joinWaitlist stores a normalized email and reports joined", async () => {
  const t = convexTest(schema, modules);

  const result = await t.mutation(api.waitlist.joinWaitlist, {
    email: "  Tony@Example.COM ",
    source: "desktop",
  });
  expect(result).toEqual({ status: "joined" });

  const rows = await t.run((ctx) => ctx.db.query("waitlist").collect());
  expect(rows).toHaveLength(1);
  expect(rows[0].email).toBe("tony@example.com");
  expect(rows[0].source).toBe("desktop");
});

test("joining the same address again is idempotent and keeps the first row", async () => {
  const t = convexTest(schema, modules);

  await t.mutation(api.waitlist.joinWaitlist, {
    email: "a@b.com",
    source: "phone",
  });
  const again = await t.mutation(api.waitlist.joinWaitlist, {
    email: "A@B.com",
    source: "desktop",
  });

  expect(again).toEqual({ status: "already" });
  const rows = await t.run((ctx) => ctx.db.query("waitlist").collect());
  expect(rows).toHaveLength(1);
  // A re-join must not overwrite the source captured the first time.
  expect(rows[0].source).toBe("phone");
});

test("an invalid email is rejected and stores nothing", async () => {
  const t = convexTest(schema, modules);

  await expect(
    t.mutation(api.waitlist.joinWaitlist, {
      email: "not-an-email",
      source: "desktop",
    }),
  ).rejects.toThrow();

  const rows = await t.run((ctx) => ctx.db.query("waitlist").collect());
  expect(rows).toHaveLength(0);
});
