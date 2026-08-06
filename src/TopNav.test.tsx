// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render } from "@testing-library/react";

import { TopNav } from "./TopNav";

afterEach(cleanup);

// Shared by every public page -- pure markup, no session and no backend, the
// same reasoning as SkyPage.test.tsx.
describe("the shared top nav", () => {
  test("the wordmark is the only link, and it goes home", () => {
    const { container } = render(<TopNav />);
    const links = Array.from(container.querySelectorAll("a")).map((a) => [
      a.textContent,
      a.getAttribute("href"),
    ]);
    expect(links).toEqual([["Haven", "/"]]);
  });

  // The links cluster ("Your Sky" / "iPhone" / "Sign in") that used to sit
  // beside the wordmark is gone site-wide, with no prop left to bring it
  // back -- this is the one place that guard belongs, rather than repeated
  // on every page that renders TopNav (see the component's own comment).
  test("renders no nav element -- brand-only, no links cluster", () => {
    const { container } = render(<TopNav />);
    expect(container.querySelector("nav")).toBeNull();
  });

  // The icon is unconditional (see the component's own comment): every
  // caller gets the Haven mascot next to the wordmark.
  test("renders the mascot icon next to the wordmark", () => {
    const { container } = render(<TopNav />);
    const icon = container.querySelector(".top-nav-brand .top-nav-icon");
    expect(icon).toBeTruthy();
    expect(icon?.getAttribute("src")).toBe("/icon-nav.png");
    expect(icon?.getAttribute("alt")).toBe("");
  });
});
