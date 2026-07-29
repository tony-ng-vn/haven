// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

import { SupportPage } from "./SupportPage";

afterEach(cleanup);

// This page exists because App Review opens the Support URL, and because the
// person most likely to open it cannot get into their account. Both facts make
// the same demand: it has to render everything it promises with no session, no
// Convex query, and no props. So the test renders it bare -- if this file ever
// needs a mock, the page has grown a dependency it must not have.

describe("the support page", () => {
  test("renders with no session, no props, and no backend", () => {
    render(<SupportPage />);
    expect(
      screen.getByRole("heading", { level: 1, name: "Support" }),
    ).toBeTruthy();
  });

  // Guideline 5.1.1(v) wants account deletion findable. It is in the app, but
  // a reviewer looking for it -- or someone locked out -- looks here, and a
  // support page that omits it invites the rejection it exists to prevent.
  test("says how to delete an account, in the app and by mail", () => {
    render(<SupportPage />);
    expect(
      screen.getByRole("heading", { name: /delete my account/i }),
    ).toBeTruthy();
    // The in-app route, named the way the app names it.
    const body = document.body.textContent ?? "";
    expect(body).toContain("My Card");
    expect(body).toContain("Delete your account");
    // And the way out for someone who cannot reach the app at all.
    expect(body).toMatch(/cannot get into the app/i);
  });

  // The one question a private notebook has to answer out loud.
  test("answers whether notes are visible to the people they are about", () => {
    render(<SupportPage />);
    expect(screen.getByRole("heading", { name: /see my notes/i })).toBeTruthy();
  });

  test("every contact route is a mailto anyone can use signed out", () => {
    render(<SupportPage />);
    const mailtos = Array.from(
      document.querySelectorAll<HTMLAnchorElement>('a[href^="mailto:"]'),
    );
    expect(mailtos.length).toBeGreaterThan(0);
    for (const link of mailtos) {
      expect(link.href).toBe("mailto:hello@inhavens.com");
    }
  });

  // The three pages App Review reaches from the listing all point at each
  // other; a dead end on any of them is a link a reviewer reports as broken.
  test("links to the policy and the terms", () => {
    render(<SupportPage />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("/privacy");
    expect(hrefs).toContain("/terms");
    expect(hrefs).toContain("/");
  });

  test("titles the tab, so a saved link reads as Haven's", () => {
    render(<SupportPage />);
    expect(document.title).toBe("Support - Haven");
  });
});
