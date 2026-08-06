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

  // The icon is opt-in (see the component's own comment on the `icon` prop):
  // this is the root-invariant guard -- every caller that renders <TopNav />
  // with no props, which includes the root landing that must stay
  // byte-identical to main, gets no icon <img> at all.
  test("renders no icon by default", () => {
    const { container } = render(<TopNav />);
    expect(container.querySelector(".top-nav-icon")).toBeNull();
  });

  test("icon opts in to the mascot image next to the wordmark", () => {
    const { container } = render(<TopNav icon />);
    const icon = container.querySelector(".top-nav-brand .top-nav-icon");
    expect(icon).toBeTruthy();
    expect(icon?.getAttribute("src")).toBe("/icon-192.png");
    expect(icon?.getAttribute("alt")).toBe("");
  });
});
