// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render } from "@testing-library/react";

import { TopNav } from "./TopNav";

afterEach(cleanup);

// Shared by the landing hero, Your Sky, and the iOS page -- pure markup, no
// session and no backend, the same reasoning as SkyPage.test.tsx.
describe("the shared top nav", () => {
  test("wordmark links home, and all three links go where they say", () => {
    const { container } = render(<TopNav />);
    const links = Array.from(container.querySelectorAll("a")).map((a) => [
      a.textContent,
      a.getAttribute("href"),
    ]);
    expect(links).toContainEqual(["Haven", "/"]);
    expect(links).toContainEqual(["Your Sky", "#/sky"]);
    expect(links).toContainEqual(["iPhone", "#/ios"]);
    expect(links).toContainEqual(["Sign in", "#/sign-in"]);
  });

  // The links cluster is opt-in-out via `links` (see the component's own
  // comment): this is the root-invariant guard -- every caller that renders
  // <TopNav /> with no props, which includes the root landing that must stay
  // byte-identical to main, still gets the full links nav by default.
  test("renders the links cluster by default", () => {
    const { container } = render(<TopNav />);
    expect(container.querySelector(".top-nav-links")).toBeTruthy();
  });

  test("links={false} hides the links cluster, keeping the wordmark", () => {
    const { container } = render(<TopNav links={false} />);
    expect(container.querySelector(".top-nav-links")).toBeNull();
    const links = Array.from(container.querySelectorAll("a")).map((a) => [
      a.textContent,
      a.getAttribute("href"),
    ]);
    expect(links).toEqual([["Haven", "/"]]);
  });

  // The icon is unconditional now (see the component's own comment): every
  // caller, including the ones that render <TopNav /> with no props at all,
  // gets the Haven mascot next to the wordmark.
  test("renders the mascot icon next to the wordmark by default", () => {
    const { container } = render(<TopNav />);
    const icon = container.querySelector(".top-nav-brand .top-nav-icon");
    expect(icon).toBeTruthy();
    expect(icon?.getAttribute("src")).toBe("/icon-192.png");
    expect(icon?.getAttribute("alt")).toBe("");
  });
});
