/// <reference types="vite/client" />
import { convexTest, type TestConvex } from "convex-test";
import { expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import { handleValueKey } from "./handleKeys";

const modules = import.meta.glob("./**/*.ts");

let nextSubject = 0;
function asNewUser(t: ReturnType<typeof convexTest>) {
  const subject = `profile_user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  const userId = `${issuer}|${subject}`;
  return { userId, as: t.withIdentity({ subject, issuer }) };
}

// convex-test's storage mock drops the Blob's contentType, so photo
// validation would always see undefined. Patch the system table directly --
// same workaround as captures.test.ts, and the same reason.
async function seedPhoto(
  t: TestConvex<typeof schema>,
  contentType = "image/jpeg",
) {
  const id = await t.run((ctx) =>
    ctx.storage.store(new Blob(["fake-photo"], { type: contentType })),
  );
  await t.run((ctx) => (ctx.db as any).patch("_storage", id, { contentType }));
  return id;
}

async function storedProfile(t: TestConvex<typeof schema>, userId: string) {
  return await t.run((ctx) =>
    ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique(),
  );
}

test("updateMyProfile creates the profile row and mints a handle from the name", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  const saved = await me.as.mutation(api.profiles.updateMyProfile, {
    name: "  Maya Chen ",
  });

  expect(saved.name).toBe("Maya Chen");
  expect(saved.username).toBe("maya");
  expect(await storedProfile(t, me.userId)).toMatchObject({
    name: "Maya Chen",
    username: "maya",
  });
});

test("getMyCard returns null until the row exists, then the whole card", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  expect(await me.as.query(api.profiles.getMyCard, {})).toBeNull();

  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    city: { name: "Ho Chi Minh City", admin: "", country: "Vietnam" },
    handles: [{ platform: "x", value: "mayachen", verified: true }],
    primaryPlatform: "x",
  });

  expect(await me.as.query(api.profiles.getMyCard, {})).toMatchObject({
    name: "Maya Chen",
    username: "maya",
    city: { name: "Ho Chi Minh City", country: "Vietnam" },
    handles: [{ platform: "x", value: "mayachen", verified: true }],
    primaryPlatform: "x",
  });
});

// Onboarding resumes at the first unanswered question, and the client decides
// that from the card alone. A card that answered for someone else would send a
// person straight past the questions they still owe.
test("getMyCard reads only the caller's own row", async () => {
  const t = convexTest(schema, modules);
  const maya = asNewUser(t);
  const other = asNewUser(t);

  await maya.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });

  expect(await other.as.query(api.profiles.getMyCard, {})).toBeNull();
});

test("updateMyProfile needs a name before it can create the row", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  await expect(
    me.as.mutation(api.profiles.updateMyProfile, { company: "Haven" }),
  ).rejects.toThrow("Enter your name first");
  expect(await storedProfile(t, me.userId)).toBeNull();
});

test("updateMyProfile leaves omitted fields untouched", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const photoStorageId = await seedPhoto(t);
  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    company: "Haven",
    role: "Founder",
    photoStorageId,
    city: { name: "Da Nang", admin: "Da Nang", country: "Vietnam" },
    handles: [{ platform: "x", value: "mayac", verified: true }],
    primaryPlatform: "x",
  });

  const saved = await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya C",
  });

  expect(saved).toMatchObject({
    name: "Maya C",
    company: "Haven",
    role: "Founder",
    photoStorageId,
    city: { name: "Da Nang", admin: "Da Nang", country: "Vietnam" },
    handles: [{ platform: "x", value: "mayac", verified: true }],
    primaryPlatform: "x",
  });
});

test("updateMyProfile clears a field when passed null", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const photoStorageId = await seedPhoto(t);
  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    company: "Haven",
    photoStorageId,
    city: { name: "Da Nang" },
  });

  await me.as.mutation(api.profiles.updateMyProfile, {
    company: null,
    photoStorageId: null,
    city: null,
  });

  const stored = await storedProfile(t, me.userId);
  expect(stored?.company).toBeUndefined();
  expect(stored?.photoStorageId).toBeUndefined();
  expect(stored?.city).toBeUndefined();
  expect(stored?.name).toBe("Maya Chen");
});

test("updateMyProfile rejects blank strings instead of storing them", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });

  await expect(
    me.as.mutation(api.profiles.updateMyProfile, { name: "   " }),
  ).rejects.toThrow("Enter your name");
  await expect(
    me.as.mutation(api.profiles.updateMyProfile, { company: "  " }),
  ).rejects.toThrow("cannot be blank");
  await expect(
    me.as.mutation(api.profiles.updateMyProfile, {
      handles: [{ platform: "x", value: " ", verified: false }],
    }),
  ).rejects.toThrow("cannot be blank");
});

test("updateMyProfile stores an accent-insensitive city key for Phase 3 filtering", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  const saved = await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    city: { name: "Đà Nẵng", country: "Vietnam" },
  });

  expect(saved.city).toMatchObject({ name: "Đà Nẵng" });
  expect((await storedProfile(t, me.userId))?.city?.normalized).toBe("da nang");
});

test("updateMyProfile allows one handle per platform only", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });

  await expect(
    me.as.mutation(api.profiles.updateMyProfile, {
      handles: [
        { platform: "x", value: "mayac", verified: true },
        { platform: "x", value: "maya_c", verified: true },
      ],
    }),
  ).rejects.toThrow("one handle per platform");
});

test("updateMyProfile folds a stored handle onto its identity key", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  const saved = await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Mai Nguyen",
    handles: [{ platform: "instagram", value: " @Mai.Makes ", verified: true }],
  });

  const stored = (await storedProfile(t, me.userId))?.handles?.[0]?.value;
  expect(stored).toBeDefined();
  expect(handleValueKey(stored as string)).toBe(handleValueKey("mai.makes"));
  // Folded for identity, not flattened for display: the card still shows the
  // capitalization its owner typed.
  expect(saved.handles?.[0]?.value).toBe("Mai.Makes");
});

test("updateMyProfile rejects a handle that is nothing but at signs", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Mai Nguyen" });

  await expect(
    me.as.mutation(api.profiles.updateMyProfile, {
      handles: [{ platform: "instagram", value: "@@", verified: false }],
    }),
  ).rejects.toThrow("cannot be blank");
});

test("updateMyProfile rejects a primary platform that is not in the handle list", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    handles: [{ platform: "x", value: "mayac", verified: true }],
  });

  await expect(
    me.as.mutation(api.profiles.updateMyProfile, {
      primaryPlatform: "linkedin",
    }),
  ).rejects.toThrow("Choose a primary platform you have a handle for");
  expect((await storedProfile(t, me.userId))?.primaryPlatform).toBeUndefined();
});

test("updateMyProfile clears the primary platform when its handle is removed", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    handles: [
      { platform: "x", value: "mayac", verified: true },
      { platform: "linkedin", value: "maya-chen", verified: false },
    ],
    primaryPlatform: "x",
  });

  const saved = await me.as.mutation(api.profiles.updateMyProfile, {
    handles: [{ platform: "linkedin", value: "maya-chen", verified: false }],
  });

  expect(saved.primaryPlatform).toBeUndefined();
  expect((await storedProfile(t, me.userId))?.primaryPlatform).toBeUndefined();
});

test("updateMyProfile keeps the primary platform when an unrelated handle is removed", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    handles: [
      { platform: "x", value: "mayac", verified: true },
      { platform: "phone", value: "+84 90 123 4567", verified: false },
    ],
    primaryPlatform: "x",
  });

  const saved = await me.as.mutation(api.profiles.updateMyProfile, {
    handles: [{ platform: "x", value: "mayac", verified: true }],
  });

  expect(saved.primaryPlatform).toBe("x");
});

test("updateMyProfile refuses a photo blob that is not an image", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });
  const notAnImage = await seedPhoto(t, "application/pdf");

  await expect(
    me.as.mutation(api.profiles.updateMyProfile, {
      photoStorageId: notAnImage,
    }),
  ).rejects.toThrow("image");
  expect((await storedProfile(t, me.userId))?.photoStorageId).toBeUndefined();
});

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
  expect((await storedProfile(t, me.userId))?.username).toBe("maya_7");
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

// The photo import and the My Card photo add both upload before they know
// which profile field the blob will land in, so the URL is its own function
// rather than a side effect of updateMyProfile.
test("generateUploadUrl hands a signed-in caller a URL", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  const url = await me.as.mutation(api.profiles.generateUploadUrl, {});

  expect(typeof url).toBe("string");
  expect(url.length).toBeGreaterThan(0);
});

// An upload URL writes a blob to storage, so it is a spend, and the sweep
// that reclaims unreferenced blobs is not a reason to let one caller open the
// tap. The cap matches captures' own createCapture burst limit.
test("generateUploadUrl is rate limited per user", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const other = asNewUser(t);

  for (let i = 0; i < 10; i++) {
    await me.as.mutation(api.profiles.generateUploadUrl, {});
  }

  await expect(
    me.as.mutation(api.profiles.generateUploadUrl, {}),
  ).rejects.toThrow("Too many");
  // One user's burst must not spend another user's budget.
  await expect(
    other.as.mutation(api.profiles.generateUploadUrl, {}),
  ).resolves.toBeTruthy();
});

// A skip is the one thing the card cannot record: a declined city and a city
// nobody has been asked for leave the same empty field. The device remembered
// it until now, which loses the answer on reinstall and lies on a second
// phone, so the server keeps it.
test("recordOnboardingStep remembers what happened to each question", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });

  await me.as.mutation(api.profiles.recordOnboardingStep, {
    step: "name",
    state: "answered",
  });
  await me.as.mutation(api.profiles.recordOnboardingStep, {
    step: "location",
    state: "skipped",
  });

  const card = await me.as.query(api.profiles.getMyCard, {});
  expect(card?.onboarding).toMatchObject({
    name: "answered",
    location: "skipped",
  });
  // Contact is untouched, not pending: a question nobody has reached yet is
  // absent, so the client can tell "not asked" from "asked and declined".
  expect(card?.onboarding?.contact).toBeUndefined();
  expect(card?.onboarding?.completedAt).toBeUndefined();
});

test("recordOnboardingStep stamps completedAt once every question is decided", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });

  for (const step of ["name", "location", "contact"] as const) {
    await me.as.mutation(api.profiles.recordOnboardingStep, {
      step,
      // Reaching the end by skipping is still reaching the end.
      state: step === "name" ? "answered" : "skipped",
    });
  }

  const first = (await me.as.query(api.profiles.getMyCard, {}))?.onboarding
    ?.completedAt;
  expect(typeof first).toBe("number");

  // Answering a question later must not restamp it: completedAt is when this
  // person got through onboarding, not when they last edited a field.
  await me.as.mutation(api.profiles.recordOnboardingStep, {
    step: "contact",
    state: "answered",
  });
  const card = await me.as.query(api.profiles.getMyCard, {});
  expect(card?.onboarding?.completedAt).toBe(first);
  expect(card?.onboarding?.contact).toBe("answered");
});

// Name is the one required answer -- the card has nothing to show without it
// and the beacon address is minted from it -- so nothing offers to skip it and
// the server does not accept a skip either.
test("recordOnboardingStep refuses to record the name question as skipped", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });

  await expect(
    me.as.mutation(api.profiles.recordOnboardingStep, {
      step: "name",
      state: "skipped",
    }),
  ).rejects.toThrow("name");
});

test("recordOnboardingStep needs a card to record against", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  await expect(
    me.as.mutation(api.profiles.recordOnboardingStep, {
      step: "location",
      state: "skipped",
    }),
  ).rejects.toThrow("Enter your name first");
});

// App Review 5.1.1: an account someone made in the app has to be deletable
// from the app. Everything the caller owns goes, and nothing anyone else owns.
test("deleteMyAccount removes the caller's profile and everything they own", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const photoStorageId = await seedPhoto(t);
  const captureBlob = await seedPhoto(t);

  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    photoStorageId,
    handles: [{ platform: "x", value: "mayachen", verified: true }],
  });
  await me.as.mutation(api.people.addPerson, {
    name: "Ada Lovelace",
    contactHandles: [{ platform: "x", value: "ada" }],
    context: "Met at a conference.",
  });
  const captureId = await t.run((ctx) =>
    ctx.db.insert("captures", {
      userId: me.userId,
      screenshotId: captureBlob,
      status: "ready" as const,
    }),
  );

  await me.as.mutation(api.profiles.deleteMyAccount, {});

  expect(await storedProfile(t, me.userId)).toBeNull();
  await t.run(async (ctx) => {
    expect(
      await ctx.db
        .query("people")
        .withIndex("by_user", (q) => q.eq("userId", me.userId))
        .collect(),
    ).toEqual([]);
    expect(
      await ctx.db
        .query("personHandles")
        .withIndex("by_user_and_platform_and_valueKey", (q) =>
          q.eq("userId", me.userId),
        )
        .collect(),
    ).toEqual([]);
    expect(await ctx.db.get("captures", captureId)).toBeNull();
    expect(
      await ctx.db
        .query("rateLimits")
        .withIndex("by_user_action", (q) => q.eq("userId", me.userId))
        .collect(),
    ).toEqual([]);
    // The blobs go with the rows. A file nobody can reach is still a file
    // we are storing about someone who asked to be forgotten.
    expect(await ctx.db.system.get(photoStorageId)).toBeNull();
    expect(await ctx.db.system.get(captureBlob)).toBeNull();
  });
});

test("deleteMyAccount leaves other people's rows alone", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const other = asNewUser(t);

  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });
  await other.as.mutation(api.profiles.updateMyProfile, {
    name: "Ada Lovelace",
  });
  await other.as.mutation(api.people.addPerson, {
    name: "Maya Chen",
    contactHandles: [{ platform: "x", value: "mayachen" }],
    context: "Met through Haven.",
  });

  await me.as.mutation(api.profiles.deleteMyAccount, {});

  expect(await storedProfile(t, other.userId)).not.toBeNull();
  // Someone else's private note about me is their row, not mine, so deleting
  // my account must not reach into their directory.
  await t.run(async (ctx) => {
    expect(
      await ctx.db
        .query("people")
        .withIndex("by_user", (q) => q.eq("userId", other.userId))
        .collect(),
    ).toHaveLength(1);
  });
});

// The row is gone the moment the mutation returns, so a second tap is not an
// error and a half-finished purge is not a dead end.
test("deleteMyAccount is safe to call twice and with no profile row", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  await expect(
    me.as.mutation(api.profiles.deleteMyAccount, {}),
  ).resolves.toBeNull();

  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });
  await me.as.mutation(api.profiles.deleteMyAccount, {});
  await expect(
    me.as.mutation(api.profiles.deleteMyAccount, {}),
  ).resolves.toBeNull();
  expect(await storedProfile(t, me.userId)).toBeNull();
});

test("profile functions reject unauthenticated callers", async () => {
  const t = convexTest(schema, modules);

  await expect(t.query(api.profiles.getMyProfile, {})).rejects.toThrow(
    "Not signed in",
  );
  await expect(t.mutation(api.profiles.generateUploadUrl, {})).rejects.toThrow(
    "Not signed in",
  );
  await expect(t.mutation(api.profiles.deleteMyAccount, {})).rejects.toThrow(
    "Not signed in",
  );
  await expect(
    t.mutation(api.profiles.recordOnboardingStep, {
      step: "location",
      state: "skipped",
    }),
  ).rejects.toThrow("Not signed in");
  await expect(t.query(api.profiles.getMyCard, {})).rejects.toThrow(
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
  await expect(
    t.mutation(api.profiles.updateMyProfile, { name: "Maya" }),
  ).rejects.toThrow("Not signed in");
  await expect(
    t.mutation(api.profiles.claimHandle, { handle: "maya" }),
  ).rejects.toThrow("Not signed in");
  // getByHandle is absent on purpose: it is the public web card page, so a
  // signed-out visitor reaching it is the whole point, not an oversight.
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
    havenContactUserId: bob.userId,
    platform: "Haven",
    handle: "bob",
  });
  expect(bobPeople[0]).toMatchObject({
    name: "@alice",
    userId: bob.userId,
    havenContactUserId: alice.userId,
    platform: "Haven",
    handle: "alice",
  });

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

test("a meetExchange person is findable by keyword search", async () => {
  const t = convexTest(schema, modules);
  const alice = asNewUser(t);
  const bob = asNewUser(t);
  await alice.as.mutation(api.profiles.setUsername, { username: "alice" });
  await bob.as.mutation(api.profiles.setUsername, { username: "bob" });

  await alice.as.mutation(api.profiles.meetExchange, { username: "bob" });

  // ensureMeetPerson bypasses addPerson, so it must feed the keyword index
  // itself -- the exchanged contact is findable by their handle.
  const hits = await alice.as.query(api.people.searchDirectory, {
    keyword: "bob",
  });
  expect(hits.map((p) => p.name)).toEqual(["@bob"]);
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
});

test("meetExchange requires a username for self and rejects self exchange", async () => {
  const t = convexTest(schema, modules);
  const alice = asNewUser(t);

  await expect(
    alice.as.mutation(api.profiles.meetExchange, { username: "bob" }),
  ).rejects.toThrow("Choose your Haven username first");

  await alice.as.mutation(api.profiles.setUsername, { username: "alice" });
  await expect(
    alice.as.mutation(api.profiles.meetExchange, { username: "alice" }),
  ).rejects.toThrow("Enter the other person's username");
});

test("claimHandle claims a free handle and is idempotent for the same caller", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });

  const first = await me.as.mutation(api.profiles.claimHandle, {
    handle: " @Maya_C ",
  });
  const again = await me.as.mutation(api.profiles.claimHandle, {
    handle: "maya_c",
  });

  expect(first).toEqual({
    status: "claimed",
    handle: "maya_c",
    suggestions: [],
  });
  expect(again).toEqual({
    status: "claimed",
    handle: "maya_c",
    suggestions: [],
  });
  // Same field the beacon URL and the legacy web flow read.
  expect(await me.as.query(api.profiles.getMyProfile, {})).toMatchObject({
    username: "maya_c",
  });
});

test("claimHandle reports taken and offers free suggestions", async () => {
  const t = convexTest(schema, modules);
  const holder = asNewUser(t);
  const me = asNewUser(t);
  await holder.as.mutation(api.profiles.claimHandle, { handle: "sky" });
  await me.as.mutation(api.profiles.updateMyProfile, { name: "Maya Chen" });

  const result = await me.as.mutation(api.profiles.claimHandle, {
    handle: "SKY",
  });

  expect(result.status).toBe("taken");
  expect(result.handle).toBe("sky");
  expect(result.suggestions[0]).toBe("maya_chen");
  expect(result.suggestions).not.toContain("sky");
  // A rejected claim leaves the caller's own handle alone.
  expect(await storedProfile(t, me.userId)).toMatchObject({
    username: "maya",
  });
});

test("claimHandle rejects a handle the beacon URL could not carry", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  await expect(
    me.as.mutation(api.profiles.claimHandle, { handle: "maya chen!" }),
  ).rejects.toThrow("3-24 lowercase letters");
  await expect(
    me.as.mutation(api.profiles.claimHandle, { handle: "maya-chen" }),
  ).rejects.toThrow("3-24 lowercase letters");
});

test("claimHandle creates the row for a caller who has no profile yet", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  const claimed = await me.as.mutation(api.profiles.claimHandle, {
    handle: "maya",
  });

  expect(claimed.status).toBe("claimed");
  expect(await storedProfile(t, me.userId)).toMatchObject({ username: "maya" });
});

test("claimHandle and setUsername write the same handle field", async () => {
  const t = convexTest(schema, modules);
  const legacy = asNewUser(t);
  const other = asNewUser(t);
  await legacy.as.mutation(api.profiles.setUsername, { username: "maya" });

  expect(
    await other.as.mutation(api.profiles.claimHandle, { handle: "maya" }),
  ).toMatchObject({ status: "taken" });

  await other.as.mutation(api.profiles.claimHandle, { handle: "maya_c" });
  expect(
    await legacy.as.query(api.profiles.lookupByUsername, {
      username: "maya_c",
    }),
  ).toEqual({ username: "maya_c" });
});

test("getByHandle serves the public card to a signed-out visitor", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const photoStorageId = await seedPhoto(t);
  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    photoStorageId,
    city: { name: "Da Nang", admin: "Da Nang", country: "Vietnam" },
    handles: [{ platform: "x", value: "mayac", verified: true }],
    primaryPlatform: "x",
  });

  // No withIdentity: this is the unauthenticated web card page.
  const card = await t.query(api.profiles.getByHandle, { handle: "@MAYA " });

  expect(card).toMatchObject({
    handle: "maya",
    name: "Maya Chen",
    city: { name: "Da Nang", admin: "Da Nang", country: "Vietnam" },
    handles: [{ platform: "x", value: "mayac", verified: true }],
    primaryPlatform: "x",
  });
  expect(card?.photoUrl).toEqual(expect.any(String));
  // The Phase 3 filter key is ours, not the visitor's.
  expect(card?.city).not.toHaveProperty("normalized");
});

test("getByHandle never exposes a phone number", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
    handles: [
      { platform: "phone", value: "+84901234567", verified: false },
      { platform: "instagram", value: "mayac", verified: false },
    ],
    primaryPlatform: "phone",
  });

  const card = await t.query(api.profiles.getByHandle, { handle: "maya" });

  expect(JSON.stringify(card)).not.toContain("84901234567");
  expect(card?.handles).toEqual([
    { platform: "instagram", value: "mayac", verified: false },
  ]);
  // Still says "phone" so the page can show a Connect call to action.
  expect(card?.primaryPlatform).toBe("phone");
});

test("getByHandle returns null for an unknown, unclaimable, or nameless handle", async () => {
  const t = convexTest(schema, modules);
  const legacy = asNewUser(t);
  await legacy.as.mutation(api.profiles.setUsername, { username: "maya" });

  // A legacy setUsername-only row has no card to show.
  expect(
    await t.query(api.profiles.getByHandle, { handle: "maya" }),
  ).toBeNull();
  expect(
    await t.query(api.profiles.getByHandle, { handle: "nobody" }),
  ).toBeNull();
  expect(
    await t.query(api.profiles.getByHandle, { handle: "not a handle!" }),
  ).toBeNull();
});

test("the address ladder walks first name, then first_last, then a number", async () => {
  const t = convexTest(schema, modules);
  const first = asNewUser(t);
  const second = asNewUser(t);
  const third = asNewUser(t);

  const one = await first.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
  });
  const two = await second.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
  });
  const three = await third.as.mutation(api.profiles.updateMyProfile, {
    name: "Maya Chen",
  });

  expect([one.username, two.username, three.username]).toEqual([
    "maya",
    "maya_chen",
    "maya_chen2",
  ]);
});

test("the address ladder drops diacritics and punctuation", async () => {
  const t = convexTest(schema, modules);
  const holder = asNewUser(t);
  const vietnamese = asNewUser(t);
  await holder.as.mutation(api.profiles.claimHandle, { handle: "dang" });

  const minted = await vietnamese.as.mutation(api.profiles.updateMyProfile, {
    name: "Đặng O'Brien",
  });

  expect(minted.username).toBe("dang_obrien");
});

test("the address ladder falls back when a name has no latin letters", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  const minted = await me.as.mutation(api.profiles.updateMyProfile, {
    name: "李雷",
  });

  expect(minted.username).toBe("haven");
});

test("the address ladder truncates a long name to a legal handle", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const other = asNewUser(t);

  const minted = await me.as.mutation(api.profiles.updateMyProfile, {
    name: "Wolfeschlegelsteinhausenbergerdorff Featherstonehaugh",
  });
  const next = await other.as.mutation(api.profiles.updateMyProfile, {
    name: "Wolfeschlegelsteinhausenbergerdorff Featherstonehaugh",
  });

  expect(minted.username).toBe("wolfeschlegelsteinhausen");
  expect(next.username).toMatch(/^[a-z0-9_]{3,24}$/);
  expect(next.username).not.toBe(minted.username);
});
