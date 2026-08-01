// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

// This page's own job is the hero composition and the lens/fine-pointer
// wiring; the nav and the demo embed each have their own dedicated tests
// (TopNav.test.tsx, SkyDemoEmbed.test.tsx), so both are stood in for here the
// way CardPage.test.tsx stands in for PersonSky.
const driftSkyProps = vi.hoisted(() => ({
  current: null as Record<string, unknown> | null,
}));
vi.mock("./DriftSky", () => ({
  DriftSky: (props: Record<string, unknown>) => {
    driftSkyProps.current = props;
    return null;
  },
}));
vi.mock("./TopNav", () => ({
  TopNav: () => <div data-testid="top-nav-stub" />,
}));
vi.mock("./SkyDemoEmbed", () => ({
  SkyDemoEmbed: () => <div data-testid="demo-embed-stub" />,
}));

const { LandingPage } = await import("./LandingPage");

const originalMatchMedia = window.matchMedia;

// A minimal MediaQueryList stand-in: only `.matches` is read (see
// prefersFinePointer in LandingPage.tsx), so nothing else needs to work.
function stubPointer(fine: boolean) {
  window.matchMedia = ((query: string) => ({
    matches: query.includes("pointer: fine") ? fine : false,
    media: query,
  })) as typeof window.matchMedia;
}

afterEach(() => {
  cleanup();
  window.matchMedia = originalMatchMedia;
  driftSkyProps.current = null;
});

// Public and unauthenticated, like the card and legal pages: this renders
// with no session, no Convex query, and no props.

describe("the Haven landing page", () => {
  test("renders with no session, no props, and no backend", () => {
    stubPointer(false);
    render(<LandingPage />);
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
    expect(screen.getByTestId("top-nav-stub")).toBeTruthy();
  });

  test("titles the tab", () => {
    stubPointer(false);
    render(<LandingPage />);
    expect(document.title).toBe(
      "Haven - A memory layer for the people you meet",
    );
  });

  // The core routing promise this page exists to keep: each product has its
  // own path onward, reachable straight from the hero, not below a scroll.
  // Sky is primary (the gold treatment its own download button uses) --
  // available today outranks a waitlist signup as the hero's main ask.
  test("the hero carries both CTAs: Sky primary, iOS secondary", () => {
    stubPointer(false);
    render(<LandingPage />);
    const sky = screen.getByText("Try Your Sky for Mac").closest("a");
    const ios = screen.getByText("Join the iPhone waitlist").closest("a");
    expect(sky?.getAttribute("href")).toBe("#/sky");
    expect(sky?.className).toContain("sky-download");
    expect(ios?.getAttribute("href")).toBe("#/ios");
  });

  test("hosts the nav and the demo embed rather than duplicating their logic", () => {
    stubPointer(false);
    render(<LandingPage />);
    expect(screen.getByTestId("top-nav-stub")).toBeTruthy();
    expect(screen.getByTestId("demo-embed-stub")).toBeTruthy();
  });

  test("the footer links to the legal and support pages", () => {
    stubPointer(false);
    render(<LandingPage />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("/privacy");
    expect(hrefs).toContain("/terms");
    expect(hrefs).toContain("/support");
  });

  test("names both products by name", () => {
    stubPointer(false);
    render(<LandingPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/your sky/i);
    expect(body).toMatch(/iphone/i);
    expect(body).toMatch(/waitlist/i);
  });

  // The placement decision this page owns: the drag-to-reveal constellation
  // figure is wired only for a fine pointer (mouse or trackpad). DriftSky's
  // own reduced-motion check still applies underneath this -- untouched here,
  // and not re-tested, since DriftSky.tsx itself did not change.
  test("passes the constellation lens into DriftSky on a fine pointer", () => {
    stubPointer(true);
    render(<LandingPage />);
    expect(driftSkyProps.current?.lens).toBe(true);
  });

  // A touch device falls back to the plain drift DriftSky already does
  // without the lens -- the gesture is not wired at all, not merely hidden.
  test("does not pass the lens on a coarse pointer", () => {
    stubPointer(false);
    render(<LandingPage />);
    expect(driftSkyProps.current?.lens).toBe(false);
  });
});
