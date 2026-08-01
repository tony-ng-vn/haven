// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

// This page's own job is the hero composition and the lens/fine-pointer
// wiring; the nav, the demo embed, and the footer each have their own
// dedicated tests (TopNav.test.tsx, SkyDemoEmbed.test.tsx, Footer.test.tsx),
// so all three are stood in for here the way CardPage.test.tsx stands in for
// PersonSky.
const driftSky = vi.hoisted(() => ({
  props: null as Record<string, unknown> | null,
  mounts: 0,
}));
vi.mock("./DriftSky", () => ({
  DriftSky: (props: Record<string, unknown>) => {
    driftSky.props = props;
    driftSky.mounts += 1;
    return null;
  },
}));
vi.mock("./TopNav", () => ({
  TopNav: () => <div data-testid="top-nav-stub" />,
}));
vi.mock("./SkyDemoEmbed", () => ({
  SkyDemoEmbed: () => <div data-testid="demo-embed-stub" />,
}));
vi.mock("./Footer", () => ({
  Footer: () => <div data-testid="footer-stub" />,
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
  driftSky.props = null;
  driftSky.mounts = 0;
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

  test("hosts the nav, the demo embed, and the footer rather than duplicating their logic", () => {
    stubPointer(false);
    render(<LandingPage />);
    expect(screen.getByTestId("top-nav-stub")).toBeTruthy();
    expect(screen.getByTestId("demo-embed-stub")).toBeTruthy();
    expect(screen.getByTestId("footer-stub")).toBeTruthy();
  });

  test("names both products by name", () => {
    stubPointer(false);
    render(<LandingPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/your sky/i);
    expect(body).toMatch(/iphone/i);
    expect(body).toMatch(/waitlist/i);
  });

  // The figure and its own wander are on for every device -- matching the
  // old full-page waitlist, which had them on every device too (see
  // waitlist-design.md). Only the interactive drag gesture is limited to a
  // fine pointer; DriftSky.tsx's gestureEnabled split (see lens.test.ts) is
  // what turns this prop into "no pointer/touch listeners attach", including
  // the one that would otherwise block scroll on a touch drag.
  test("the sky wanders on every device; the drag gesture is fine-pointer only", () => {
    stubPointer(true);
    render(<LandingPage />);
    expect(driftSky.props?.lens).toBe(true);
    expect(driftSky.props?.interactive).toBe(true);
  });

  test("a coarse pointer still gets the wandering figure, never the drag gesture", () => {
    stubPointer(false);
    render(<LandingPage />);
    expect(driftSky.props?.lens).toBe(true);
    expect(driftSky.props?.interactive).toBe(false);
  });

  // The sky is a page-wide fixed background now (see .landing-sky in
  // index.css), not a canvas scoped to the hero -- className is the seam
  // between this component and the CSS that makes it full-page and full
  // presence; driftSkyCanvasSizing.test.ts pins the CSS side.
  test("mounts DriftSky once, full-page, not once per section", () => {
    stubPointer(false);
    render(<LandingPage />);
    expect(driftSky.mounts).toBe(1);
    expect(driftSky.props?.className).toBe("landing-sky");
  });
});
