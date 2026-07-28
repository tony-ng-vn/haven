/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

let nextSubject = 0;
function asNewUser(t: ReturnType<typeof convexTest>) {
  const subject = `love_alarm_user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  return t.withIdentity({ subject, issuer });
}

test("Love Alarm room only returns active opted-in peers", async () => {
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules);
    const me = asNewUser(t);
    const peer = asNewUser(t);
    const otherRoom = asNewUser(t);

    const started = await me.mutation(api.loveAlarm.startPresence, {
      roomCode: "quiet-room",
      displayName: "Me",
    });
    await peer.mutation(api.loveAlarm.startPresence, {
      roomCode: "quiet-room",
      displayName: "Maya",
    });
    await otherRoom.mutation(api.loveAlarm.startPresence, {
      roomCode: "other-room",
      displayName: "Felix",
    });

    const nearby = await me.query(api.loveAlarm.nearby, {
      roomCode: started.roomCode,
    });

    expect(nearby.roomCode).toBe("QUIET-ROOM");
    expect(nearby.peers).toEqual([
      expect.objectContaining({ displayName: "Maya" }),
    ]);
  } finally {
    vi.useRealTimers();
  }
});

test("Love Alarm presence expires without a heartbeat", async () => {
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules);
    const me = asNewUser(t);
    const peer = asNewUser(t);

    await me.mutation(api.loveAlarm.startPresence, {
      roomCode: "stage",
      displayName: "Me",
    });
    await peer.mutation(api.loveAlarm.startPresence, {
      roomCode: "stage",
      displayName: "Maya",
    });

    vi.advanceTimersByTime(121_000);

    const nearby = await me.query(api.loveAlarm.nearby, { roomCode: "stage" });
    expect(nearby.peers).toEqual([]);
  } finally {
    vi.useRealTimers();
  }
});

test("Love Alarm rejects unauthenticated presence", async () => {
  const t = convexTest(schema, modules);

  await expect(
    t.mutation(api.loveAlarm.startPresence, { roomCode: "room" }),
  ).rejects.toThrow("Not signed in");
});

test("the sweep deletes presence rows that have expired and keeps the rest", async () => {
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules);
    const gone = asNewUser(t);
    const here = asNewUser(t);
    await gone.mutation(api.loveAlarm.startPresence, {
      roomCode: "stage",
      displayName: "Left the room",
    });

    vi.advanceTimersByTime(121_000);
    await here.mutation(api.loveAlarm.startPresence, {
      roomCode: "stage",
      displayName: "Still here",
    });

    const deleted = await t.mutation(internal.loveAlarm.sweepExpiredPresence, {});

    expect(deleted).toBe(1);
    const rows = await t.run((ctx) =>
      ctx.db.query("loveAlarmPresence").collect(),
    );
    // Expired rows are filtered on read, so nobody sees them -- but the row
    // still names a person and the room they were in, which is a fact about
    // where somebody was, kept past the two minutes they opted in for.
    expect(rows.map((row) => row.displayName)).toEqual(["Still here"]);
  } finally {
    vi.useRealTimers();
  }
});

test("the sweep is a no-op when nothing has expired", async () => {
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules);
    const me = asNewUser(t);
    await me.mutation(api.loveAlarm.startPresence, { roomCode: "stage" });

    expect(
      await t.mutation(internal.loveAlarm.sweepExpiredPresence, {}),
    ).toBe(0);
    expect(
      await t.run((ctx) => ctx.db.query("loveAlarmPresence").collect()),
    ).toHaveLength(1);
  } finally {
    vi.useRealTimers();
  }
});
