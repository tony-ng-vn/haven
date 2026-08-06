// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { act, cleanup, render, screen, waitFor } from "@testing-library/react";

// Mirrors LandingPage.test.tsx: this page's own job is the elevated
// typography/motion/focus treatment and the below-fold reveal wiring: the
// nav, the demo embed, and the footer each have their own dedicated tests, so
// all three are stood in for here the same way LandingPage's test does.
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

const { PolishedLandingPage } = await import("./PolishedLandingPage");

const originalMatchMedia = window.matchMedia;
const originalIntersectionObserver = window.IntersectionObserver;

function stubPointer(fine: boolean) {
  window.matchMedia = ((query: string) => ({
    matches: query.includes("pointer: fine") ? fine : false,
    media: query,
  })) as typeof window.matchMedia;
}

// A minimal IntersectionObserver stand-in: captures every instance's
// callback and target so a test can fire it by hand, matching how the real
// browser API is used here (one entry per observe() call).
const observers: Array<{
  callback: IntersectionObserverCallback;
  elements: Element[];
  disconnect: () => void;
}> = [];

function stubIntersectionObserver() {
  observers.length = 0;
  class StubObserver {
    private entry: { callback: IntersectionObserverCallback; elements: Element[]; disconnect: () => void };
    constructor(callback: IntersectionObserverCallback) {
      this.entry = { callback, elements: [], disconnect: () => {} };
      observers.push(this.entry);
    }
    observe(el: Element) {
      this.entry.elements.push(el);
    }
    disconnect() {
      this.entry.elements = [];
    }
    unobserve() {}
    takeRecords() {
      return [];
    }
  }
  window.IntersectionObserver = StubObserver as unknown as typeof IntersectionObserver;
}

beforeEach(() => {
  stubIntersectionObserver();
});

afterEach(() => {
  cleanup();
  window.matchMedia = originalMatchMedia;
  window.IntersectionObserver = originalIntersectionObserver;
  driftSky.props = null;
  driftSky.mounts = 0;
});

describe("the polished landing page", () => {
  test("renders with no session, no props, and no backend", () => {
    stubPointer(false);
    render(<PolishedLandingPage />);
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
    expect(screen.getByTestId("top-nav-stub")).toBeTruthy();
  });

  test("titles the tab", () => {
    stubPointer(false);
    render(<PolishedLandingPage />);
    expect(document.title).toBe("Haven - Landing");
  });

  test("the hero carries both CTAs: Sky primary, iOS secondary", () => {
    stubPointer(false);
    render(<PolishedLandingPage />);
    const sky = screen.getByText("Sky app, coming soon").closest("a");
    const ios = screen.getByText("Join the iPhone waitlist").closest("a");
    expect(sky?.getAttribute("href")).toBe("#/sky");
    expect(sky?.className).toContain("sky-download");
    expect(ios?.getAttribute("href")).toBe("#/ios");
  });

  test("hosts the nav, the demo embed, and the footer rather than duplicating their logic", () => {
    stubPointer(false);
    render(<PolishedLandingPage />);
    expect(screen.getByTestId("top-nav-stub")).toBeTruthy();
    expect(screen.getByTestId("demo-embed-stub")).toBeTruthy();
    expect(screen.getByTestId("footer-stub")).toBeTruthy();
  });

  test("names both products by name", () => {
    stubPointer(false);
    render(<PolishedLandingPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/your sky/i);
    expect(body).toMatch(/iphone/i);
    expect(body).toMatch(/waitlist/i);
  });

  test("the sky wanders on every device; the drag gesture is fine-pointer only", () => {
    stubPointer(true);
    render(<PolishedLandingPage />);
    expect(driftSky.props?.lens).toBe(true);
    expect(driftSky.props?.interactive).toBe(true);
  });

  test("a coarse pointer still gets the wandering figure, never the drag gesture", () => {
    stubPointer(false);
    render(<PolishedLandingPage />);
    expect(driftSky.props?.lens).toBe(true);
    expect(driftSky.props?.interactive).toBe(false);
  });

  // Reused, not copied: the same host class the default landing uses, so the
  // full-page fixed positioning is the one already pinned by
  // driftSkyCanvasSizing.test.ts rather than a second copy of that CSS.
  test("mounts DriftSky once, on the same full-page host class as the default landing", () => {
    stubPointer(false);
    render(<PolishedLandingPage />);
    expect(driftSky.mounts).toBe(1);
    expect(driftSky.props?.className).toBe("landing-sky");
  });

  // The root carries the scope class every elevated style hangs off, so a
  // future edit that accidentally drops it fails loudly here rather than by
  // a silent style regression on preview.
  test("scopes itself under landing-polished, alongside the base landing layout", () => {
    stubPointer(false);
    const { container } = render(<PolishedLandingPage />);
    const root = container.firstElementChild!;
    expect(root.className).toContain("landing");
    expect(root.className).toContain("landing-polished");
  });

  // The hero's own entrance: index.css keys the staggered rise-and-fade off
  // this attribute (".landing-polished[data-mounted] ..."); this pins the JS
  // side of that contract without asserting on computed style, which
  // happy-dom does not resolve through @media or transition-delay anyway.
  // Written via a ref (see PolishedLandingPage.tsx's own comment), not
  // React state, so it is absent on the very first paint and only appears
  // after the mount effect runs -- waitFor covers that one-tick gap.
  test("flips data-mounted after mount, driving the hero entrance", async () => {
    stubPointer(false);
    const { container } = render(<PolishedLandingPage />);
    const root = container.firstElementChild!;
    await waitFor(() => {
      expect(root.getAttribute("data-mounted")).toBe("true");
    });
  });

  // Below-fold reveal: each section starts unrevealed and only gains the
  // reveal class once its own IntersectionObserver reports it on screen --
  // and only once, matching the "no continuous motion" rule in the brief.
  test("a below-fold section reveals once it is observed intersecting, and only then", () => {
    stubPointer(false);
    const { container } = render(<PolishedLandingPage />);
    const sections = container.querySelectorAll(".landing-section");
    expect(sections.length).toBe(2);
    sections.forEach((section) =>
      expect(section.className).not.toContain("landing-polished-in-view"),
    );

    expect(observers.length).toBe(2);
    act(() => {
      observers[0].callback(
        [{ isIntersecting: true } as IntersectionObserverEntry],
        observers[0] as unknown as IntersectionObserver,
      );
    });
    expect(sections[0].className).toContain("landing-polished-in-view");
    expect(sections[1].className).not.toContain("landing-polished-in-view");
  });
});
