// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

// The join form is Convex-backed (useMutation) and already has its own
// extraction; this page's own job -- introducing Haven for iPhone and hosting
// that form -- is what is under test here, so the form is stood in for rather
// than run against a mocked deployment.
vi.mock("./WaitlistForm", () => ({
  WaitlistForm: () => <div data-testid="waitlist-form-stub" />,
}));

const { IosPage } = await import("./IosPage");

afterEach(cleanup);

describe("the iOS product page", () => {
  test("renders with no session, no props, and no backend", () => {
    render(<IosPage />);
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
  });

  test("titles the tab", () => {
    render(<IosPage />);
    expect(document.title).toBe("Haven for iPhone - Haven");
  });

  test("hosts the waitlist form rather than duplicating its logic", () => {
    render(<IosPage />);
    expect(screen.getByTestId("waitlist-form-stub")).toBeTruthy();
  });

  test("is honest that the iPhone app is still in development", () => {
    render(<IosPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/in development/i);
  });

  test("links back to the front door", () => {
    render(<IosPage />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("/");
  });

  // The compliance footer's own contents are pinned in Footer.test.tsx; this
  // just confirms the page actually hosts it rather than duplicating it.
  test("carries the shared compliance footer", () => {
    render(<IosPage />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("/privacy");
  });
});
