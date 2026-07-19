import { afterEach, describe, expect, test, vi } from "vitest";
import { withScreenTransition } from "./App";

// Regressed once before (commit 966afae): a skipped/aborted view transition
// rejects `finished`, and that rejection must never suppress `done`.

const originalMatchMedia = window.matchMedia;

function stubMatchMedia(reduceMotion: boolean) {
  window.matchMedia = vi.fn(() => ({ matches: reduceMotion })) as never;
}

afterEach(() => {
  window.matchMedia = originalMatchMedia;
  vi.unstubAllGlobals();
});

describe("withScreenTransition", () => {
  test("runs update then done directly when the platform has no View Transitions API", () => {
    stubMatchMedia(false);
    vi.stubGlobal("document", {
      visibilityState: "visible",
      startViewTransition: undefined,
    });
    const update = vi.fn();
    const done = vi.fn();

    withScreenTransition(update, done);

    expect(update).toHaveBeenCalledTimes(1);
    expect(done).toHaveBeenCalledTimes(1);
  });

  test("runs update then done directly under reduced motion, even when the API exists", () => {
    stubMatchMedia(true);
    const startViewTransition = vi.fn();
    vi.stubGlobal("document", {
      visibilityState: "visible",
      startViewTransition,
    });
    const update = vi.fn();
    const done = vi.fn();

    withScreenTransition(update, done);

    expect(update).toHaveBeenCalledTimes(1);
    expect(done).toHaveBeenCalledTimes(1);
    expect(startViewTransition).not.toHaveBeenCalled();
  });

  test("still runs done when the transition's finished promise rejects", async () => {
    stubMatchMedia(false);
    const update = vi.fn();
    const done = vi.fn();
    const startViewTransition = vi.fn((callback: () => void) => {
      callback();
      return { finished: Promise.reject(new Error("skipped")) };
    });
    vi.stubGlobal("document", {
      visibilityState: "visible",
      startViewTransition,
    });

    withScreenTransition(update, done);

    // The transition's own update callback runs synchronously inside
    // startViewTransition, but `done` only follows once `finished` settles.
    expect(update).toHaveBeenCalledTimes(1);
    expect(done).not.toHaveBeenCalled();

    await vi.waitFor(() => {
      expect(done).toHaveBeenCalledTimes(1);
    });
  });
});
