// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";

const { Landing2Page } = await import("./Landing2Page");

afterEach(() => {
  cleanup();
});

describe("Landing2Page", () => {
  test("renders with no session, no props, and no backend", () => {
    render(<Landing2Page />);
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
  });

  test("titles the tab", () => {
    render(<Landing2Page />);
    expect(document.title).toBe("Haven - Landing 2");
  });

  // The <br/> that breaks the headline after "Your people" splits it across
  // two text nodes at the DOM level; textContent still concatenates them, so
  // this is the one assertion that would catch a lost word or a missing
  // space at the break as easily as a lost line-break would.
  test("the headline reads as one sentence, broken after \"Your people\"", () => {
    render(<Landing2Page />);
    const heading = screen.getByRole("heading", { level: 1 });
    expect(heading.textContent?.replace(/\s+/g, " ").trim()).toBe(
      "Your people are a constellation.",
    );
    expect(heading.querySelector("br")).toBeTruthy();
  });

  test("carries the exact body copy from the brief", () => {
    render(<Landing2Page />);
    expect(
      screen.getByText(
        "Each person is beautiful on their own, but too often distant and disconnected. Haven helps you remember people, reconnect, and bring your world together.",
      ),
    ).toBeTruthy();
  });

  test("the quiet note matches the default landing's own copy", () => {
    render(<Landing2Page />);
    expect(screen.getByText("Free, runs on your Mac.")).toBeTruthy();
  });

  // Same CTA copy and hrefs as the polished landing's hero, and the same
  // button classes -- see index.css's own comment on why: press/hover/focus
  // behavior is meant to match exactly, via the shared .landing-polished
  // scope this page's root also carries.
  test("the hero carries both CTAs: Sky primary, iOS secondary", () => {
    render(<Landing2Page />);
    const sky = screen.getByText("Sky app, coming soon").closest("a");
    const ios = screen.getByText("Join the iPhone waitlist").closest("a");
    expect(sky?.getAttribute("href")).toBe("#/sky");
    expect(sky?.className).toContain("sky-download");
    expect(ios?.getAttribute("href")).toBe("#/ios");
    expect(ios?.className).toContain("landing-cta-secondary");
  });

  test("hosts the nav and the footer rather than duplicating their logic", () => {
    render(<Landing2Page />);
    // TopNav and Footer are not stubbed here (unlike LandingPage.test.tsx):
    // both are trivial and already covered by their own dedicated tests, so
    // rendering them for real is simpler than adding two more module mocks.
    expect(screen.getByText("Haven", { selector: ".top-nav-brand" })).toBeTruthy();
    expect(screen.getByText("Privacy", { selector: ".site-footer-links a" })).toBeTruthy();
  });

  // No DriftSky, no shard/seam/reveal DOM at all -- the art is the sky now.
  test("has no DriftSky canvas and no leftover glass-shard DOM", () => {
    const { container } = render(<Landing2Page />);
    expect(container.querySelector("canvas")).toBeNull();
    expect(container.querySelector(".landing2-shard")).toBeNull();
    expect(container.querySelector(".landing2-beneath")).toBeNull();
  });

  // Decorative art: the surrounding copy already carries the page's message
  // (see the component's own comment for the reasoning), so an empty alt is
  // the deliberate choice here, not an oversight.
  test("the art image is present, decorative, and points at the given asset", () => {
    const { container } = render(<Landing2Page />);
    const img = container.querySelector("img")!;
    expect(img).toBeTruthy();
    expect(img.getAttribute("src")).toBe("/glass-hero.jpg");
    expect(img.getAttribute("alt")).toBe("");
  });

  // The mount flag is written straight to the DOM via a ref (see the
  // component's own comment) -- this is the JS half of the CSS entrance
  // contract in index.css (".landing-polished[data-mounted] ...").
  test("flips data-mounted after mount, driving the entrance", async () => {
    const { container } = render(<Landing2Page />);
    const root = container.firstElementChild!;
    await waitFor(() => {
      expect(root.getAttribute("data-mounted")).toBe("true");
    });
  });

  // The root carries both classes deliberately: landing2 for this page's own
  // layout, landing-polished so it inherits Satoshi and the shared
  // press/hover/focus/entrance CSS rather than duplicating any of it.
  test("scopes itself under landing-polished, alongside its own landing2 layout", () => {
    const { container } = render(<Landing2Page />);
    const root = container.firstElementChild!;
    expect(root.className).toContain("landing2");
    expect(root.className).toContain("landing-polished");
  });

  // Reduced motion has no JS branch to test here (unlike the old shard
  // reveal, which computed inline transforms in JS) -- the entrance is pure
  // CSS, gated entirely by a @media query in index.css, so mounting under a
  // reduced-motion environment is just an ordinary render with no special
  // path to fall over on.
  test("mounts clean under a reduced-motion environment", () => {
    const original = window.matchMedia;
    window.matchMedia = ((query: string) => ({
      matches: query.includes("prefers-reduced-motion"),
      media: query,
    })) as typeof window.matchMedia;
    try {
      render(<Landing2Page />);
      expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
    } finally {
      window.matchMedia = original;
    }
  });
});
