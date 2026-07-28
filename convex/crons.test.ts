/// <reference types="vite/client" />
import { expect, test } from "vitest";
import crons from "./crons";

const modules = import.meta.glob("./**/*.ts");

// A cron holds its target as a string path, resolved by name at run time on
// the deployment. Nothing checks that name at build time, at deploy time, or
// in any other test: rename or move the function it points at and the cron
// keeps deploying, keeps its entry in the dashboard, and silently never runs
// again. Every one of ours is a self-heal -- stuck captures, orphaned blobs,
// missing embeddings -- so the failure mode is Haven quietly stopping to
// repair itself, which is exactly the kind of thing nobody notices.
test("every registered cron points at a function that exists", async () => {
  const jobs = Object.entries(crons.crons);
  // A crons.ts that registered nothing would pass every assertion below
  // without making any of them.
  expect(jobs.length).toBeGreaterThan(0);

  for (const [identifier, job] of jobs) {
    const [modulePath, exportName] = job.name.split(":");
    expect(
      { identifier, modulePath, exportName },
      `cron "${identifier}" has a malformed target`,
    ).toMatchObject({ modulePath: expect.any(String) });

    const load = modules[`./${modulePath}.ts`];
    expect(load, `cron "${identifier}" names no module ${modulePath}.ts`).toBeDefined();

    const module = (await load()) as Record<string, unknown>;
    const target = module[exportName] as
      | { isMutation?: boolean; isAction?: boolean }
      | undefined;
    expect(
      target,
      `cron "${identifier}" names ${job.name}, which that module does not export`,
    ).toBeDefined();
    // Convex only schedules mutations and actions; a query would deploy and
    // then fail on every tick.
    expect(
      target?.isMutation === true || target?.isAction === true,
      `cron "${identifier}" names ${job.name}, which is not a schedulable function`,
    ).toBe(true);
  }
});
