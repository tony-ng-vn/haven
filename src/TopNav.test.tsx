// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render } from "@testing-library/react";

import { TopNav } from "./TopNav";

afterEach(cleanup);

// Shared by every public page -- pure markup, no session and no backend, the
// same reasoning as SkyPage.test.tsx.
describe("the shared top nav", () => {
  test("the wordmark goes home and preview access sits at the right", () => {
    const { container } = render(<TopNav />);
    const links = Array.from(container.querySelectorAll("a")).map((a) => [
      a.textContent,
      a.getAttribute("href"),
    ]);
    expect(links).toEqual([
      ["Haven", "/"],
      ["Preview access", "/preview"],
    ]);
  });

  test("labels the preview link as navigation", () => {
    const { container } = render(<TopNav />);
    expect(container.querySelector("nav")?.getAttribute("aria-label")).toBe(
      "Preview",
    );
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
