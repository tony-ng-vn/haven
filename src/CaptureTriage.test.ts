import { afterEach, describe, expect, test, vi } from "vitest";
import { uploadScreenshot } from "./CaptureTriage";
import type { Id } from "../convex/_generated/dataModel";

// The one piece of CaptureTriage with real logic outside React: whether a
// single screenshot upload counts as a success or a failure. Bug: the old
// handleFiles never checked response.ok and let one bad file void the
// whole Promise.all, silently dropping every capture in the batch.

function makeDeps() {
  return {
    generateUploadUrl: vi.fn(async () => "https://upload.example/put"),
    createCapture: vi.fn(async (_args: { screenshotId: Id<"_storage"> }) => "cap_1"),
  };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("uploadScreenshot", () => {
  test("registers the capture when the storage PUT succeeds", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response(JSON.stringify({ storageId: "storage_1" }), { status: 200 }),
      ),
    );
    const deps = makeDeps();
    const file = new File(["fake"], "shot.png", { type: "image/png" });

    const ok = await uploadScreenshot(file, deps);

    expect(ok).toBe(true);
    expect(deps.createCapture).toHaveBeenCalledWith({ screenshotId: "storage_1" });
  });

  test("fails without throwing when the storage PUT responds non-ok", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("nope", { status: 500 })));
    const deps = makeDeps();
    const file = new File(["fake"], "shot.png", { type: "image/png" });

    const ok = await uploadScreenshot(file, deps);

    expect(ok).toBe(false);
    expect(deps.createCapture).not.toHaveBeenCalled();
  });

  test("fails without throwing when the network request itself rejects", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("network down");
      }),
    );
    const deps = makeDeps();
    const file = new File(["fake"], "shot.png", { type: "image/png" });

    const ok = await uploadScreenshot(file, deps);

    expect(ok).toBe(false);
  });

  test("one failing file does not stop the others in a batch", async () => {
    let call = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        call += 1;
        if (call === 1) return new Response("nope", { status: 500 });
        return new Response(JSON.stringify({ storageId: "storage_ok" }), {
          status: 200,
        });
      }),
    );
    const deps = makeDeps();
    const bad = new File(["bad"], "bad.png", { type: "image/png" });
    const good = new File(["good"], "good.png", { type: "image/png" });

    const results = await Promise.all([
      uploadScreenshot(bad, deps),
      uploadScreenshot(good, deps),
    ]);

    expect(results).toEqual([false, true]);
    expect(deps.createCapture).toHaveBeenCalledTimes(1);
  });
});
