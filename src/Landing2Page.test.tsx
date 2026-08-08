// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";

// This page's own job is the hero composition, not DriftSky's own animation
// loop (driftSkyCanvasSizing.test.ts already pins the canvas's sizing), so
// DriftSky is the only thing stubbed here. TopNav itself is NOT stubbed (see
// the existing "hosts the nav and the footer" test below) -- it is trivial,
// already covered by its own dedicated test, and rendering it for real is
// what lets this file assert the icon prop actually reaches real markup.
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

const { Landing2Page } = await import("./Landing2Page");

afterEach(() => {
  cleanup();
  driftSky.props = null;
  driftSky.mounts = 0;
});

describe("Landing2Page", () => {
  test("renders with no session, no props, and no backend", () => {
    render(<Landing2Page />);
    expect(screen.getByRole("heading", { level: 1 })).toBeTruthy();
    expect(screen.queryByRole("img", { name: "Festival QR code" })).toBeNull();
  });

  test("adds the festival QR card only for the festival variant", () => {
    render(<Landing2Page festival />);
    const qr = screen.getByRole("img", { name: "Festival QR code" });
    expect(qr.getAttribute("src")).toBe("/festival-qr.png");
    expect(screen.getByText("Scan at the festival")).toBeTruthy();
  });

  test("titles the tab", () => {
    render(<Landing2Page />);
    // The front door must render the same title index.html ships statically:
    // the "(Inhavens)" token is load-bearing for brand search (seo.test.ts).
    expect(document.title).toBe(
      "Haven (Inhavens) - A personal memory layer for your people",
    );
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

  test("the quiet note sets the expectation for a founder conversation", () => {
    render(<Landing2Page />);
    expect(
      screen.getByText("A conversation about people, memory, and connection."),
    ).toBeTruthy();
  });

  // Real pathnames, not the old hash routes: this is the front door now, and
  // its own two buttons point straight at /sky and /waitlist rather than at
  // "#/sky"/"#/ios" -- see hashRedirectTarget in lib.ts for how the old
  // hashes still reach the same pages. Same button classes as before: press/
  // hover/focus behavior is meant to match exactly, via the shared
  // .landing-polished scope this page's root also carries.
  test("the hero leads with booking a call and keeps the waitlist secondary", () => {
    render(<Landing2Page />);
    const call = screen.getByText("Book a call").closest("a");
    const ios = screen.getByText("Join the iPhone waitlist").closest("a");
    expect(call?.getAttribute("href")).toBe("https://cal.com/tony-nguyen-vn17");
    expect(call?.className).toContain("sky-download");
    expect(ios?.getAttribute("href")).toBe("/waitlist");
    expect(ios?.className).toContain("landing-cta-secondary");
    expect(screen.queryByText(/sky app/i)).toBeNull();
  });

  test("hosts the nav and the footer rather than duplicating their logic", () => {
    render(<Landing2Page />);
    // TopNav and Footer are not stubbed here: both are trivial and already
    // covered by their own dedicated tests, so rendering them for real is
    // simpler than adding two more module mocks.
    expect(screen.getByText("Haven", { selector: ".top-nav-brand" })).toBeTruthy();
    expect(screen.getByText("Privacy", { selector: ".site-footer-links a" })).toBeTruthy();
  });

  // The mascot icon is unconditional on TopNav now (see its own comment);
  // this just confirms this page still gets it via the real TopNav render
  // above rather than a prop passed to a stub.
  test("shows the Haven mascot icon next to the wordmark", () => {
    const { container } = render(<Landing2Page />);
    const icon = container.querySelector(".top-nav-brand .top-nav-icon");
    expect(icon).toBeTruthy();
    expect(icon?.getAttribute("src")).toBe("/icon-nav.png");
    expect(icon?.getAttribute("alt")).toBe("");
  });

  // Reused, not copied: the same host class driftSkyCanvasSizing.test.ts
  // pins the sizing/masking for, so this page's own test only needs to check
  // that DriftSky is actually mounted on it, not re-check the CSS.
  test("mounts DriftSky once, on the hero's own host class", () => {
    render(<Landing2Page />);
    expect(driftSky.mounts).toBe(1);
    expect(driftSky.props?.className).toBe("landing2-sky");
    expect(driftSky.props?.lens).toBe(true);
  });

  // No leftover shard/seam/reveal DOM from the earlier CSS-only version of
  // this page (see the component's own header comment) -- DriftSky itself is
  // stubbed above, so it is not what this guards.
  test("has no leftover glass-shard DOM", () => {
    const { container } = render(<Landing2Page />);
    expect(container.querySelector(".landing2-shard")).toBeNull();
    expect(container.querySelector(".landing2-beneath")).toBeNull();
  });

  // Decorative art: the surrounding copy already carries the page's message
  // (see the component's own comment for the reasoning), so an empty alt is
  // the deliberate choice here, not an oversight. Scoped to .landing2-art
  // (not a bare "img" query) since the nav icon is now a second <img> on
  // this page, earlier in the DOM.
  test("the art image is present, decorative, and points at the given asset", () => {
    const { container } = render(<Landing2Page />);
    const img = container.querySelector(".landing2-art img")!;
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
