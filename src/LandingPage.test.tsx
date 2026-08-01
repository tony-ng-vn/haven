// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

import { LandingPage } from "./LandingPage";

afterEach(cleanup);

// Public and unauthenticated, like the card and legal pages: this renders
// with no session, no Convex query, and no props.

describe("the Haven landing page", () => {
  test("renders with no session, no props, and no backend", () => {
    render(<LandingPage />);
    expect(screen.getByText("Haven")).toBeTruthy();
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
  });

  test("titles the tab", () => {
    render(<LandingPage />);
    expect(document.title).toBe("Haven - A memory layer for the people you meet");
  });

  // The core routing promise this page exists to keep: each product has its
  // own path onward, and the person landing here can reach either in one tap.
  test("links to both products", () => {
    render(<LandingPage />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("#/sky");
    expect(hrefs).toContain("#/ios");
  });

  // Anyone who held a link to the root expecting the waitlist must still find
  // it one click away, and on a phone the two cards stack -- so the iPhone
  // card has to be the one that stays above the fold, not the one a scroll
  // reveals second.
  test("the iPhone waitlist path comes before the Sky download path", () => {
    render(<LandingPage />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs.indexOf("#/ios")).toBeLessThan(hrefs.indexOf("#/sky"));
  });

  test("names both products by name", () => {
    render(<LandingPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/your sky/i);
    expect(body).toMatch(/iphone/i);
    expect(body).toMatch(/waitlist/i);
  });
});
