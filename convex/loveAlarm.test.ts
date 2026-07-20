/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test, vi } from "vitest";
import { api } from "./_generated/api";
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

test("Love Alarm prefers the joiner's Euno username when set", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const peer = asNewUser(t);

  await peer.mutation(api.profiles.setUsername, { username: "maya" });
  await me.mutation(api.loveAlarm.startPresence, {
    roomCode: "lobby",
    displayName: "Me",
  });
  await peer.mutation(api.loveAlarm.startPresence, { roomCode: "lobby" });

  const nearby = await me.query(api.loveAlarm.nearby, { roomCode: "lobby" });
  expect(nearby.peers).toEqual([
    expect.objectContaining({
      displayName: "@maya",
      username: "maya",
    }),
  ]);
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
