// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";

// DriftSky is stubbed the same way LandingPage.test.tsx stubs it: this page's
// own job is the layering, the copy, and the reveal interaction, not the
// star-field animation, which has its own tests (lens.test.ts, DriftSky's own
// canvas-sizing regression coverage).
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

const originalMatchMedia = window.matchMedia;

// A minimal MediaQueryList stand-in covering both queries this page reads at
// mount (prefersFinePointer, prefersReducedMotion) -- only `.matches` is ever
// read, so nothing else needs to work.
function stubMedia({ fine = false, reduced = false }: { fine?: boolean; reduced?: boolean }) {
  window.matchMedia = ((query: string) => ({
    matches: query.includes("pointer: fine")
      ? fine
      : query.includes("prefers-reduced-motion")
        ? reduced
        : false,
    media: query,
  })) as typeof window.matchMedia;
}

afterEach(() => {
  cleanup();
  window.matchMedia = originalMatchMedia;
  driftSky.props = null;
  driftSky.mounts = 0;
});

describe("Landing2Page", () => {
  test("renders with no session, no props, and no backend", () => {
    stubMedia({ fine: true });
    render(<Landing2Page />);
    expect(screen.getByText("YOUR SKY, FOR MAC")).toBeTruthy();
  });

  test("titles the tab", () => {
    stubMedia({ fine: true });
    render(<Landing2Page />);
    expect(document.title).toBe("Haven - Landing 2");
  });

  test("mounts a single, non-lens DriftSky as the beneath layer", () => {
    stubMedia({ fine: true });
    render(<Landing2Page />);
    expect(driftSky.mounts).toBe(1);
    expect(driftSky.props?.className).toBe("landing2-sky");
    expect(driftSky.props?.lens).toBeUndefined();
  });

  test("both product headings render", () => {
    stubMedia({ fine: true });
    render(<Landing2Page />);
    expect(screen.getByText("YOUR SKY, FOR MAC")).toBeTruthy();
    expect(screen.getByText("HAVEN, FOR IPHONE")).toBeTruthy();
  });

  // The owner's own reference prompt names these seven fragments verbatim;
  // this pins them so a future edit cannot silently drop or reword one.
  test("all seven faint in-glass fragments render", () => {
    stubMedia({ fine: true });
    render(<Landing2Page />);
    for (const fragment of [
      "late night",
      "alex",
      "miss you",
      "good morning",
      "dinner",
      "mom",
      "be back soon",
    ]) {
      expect(screen.getByText(fragment)).toBeTruthy();
    }
  });

  test("CTA hrefs point at the right routes", () => {
    stubMedia({ fine: true });
    render(<Landing2Page />);
    const sky = screen.getByText("Get Your Sky for Mac").closest("a");
    const ios = screen.getByText("Join the waitlist").closest("a");
    expect(sky?.getAttribute("href")).toBe("#/sky");
    expect(sky?.className).toContain("sky-download");
    expect(ios?.getAttribute("href")).toBe("#/ios");
  });

  test("the sample-sky link opens the demo in a new tab, safely", () => {
    stubMedia({ fine: true });
    render(<Landing2Page />);
    const demo = screen.getByText("Explore a sample sky").closest("a");
    expect(demo?.getAttribute("href")).toBe("/demo-sky.html");
    expect(demo?.getAttribute("target")).toBe("_blank");
    expect(demo?.getAttribute("rel")).toBe("noopener noreferrer");
  });

  // Desktop: hover reveals, and nothing here needs to special-case the
  // interactive content -- mouseenter/mouseleave only fire on the root's own
  // boundary crossing (see Landing2Page.tsx's comment).
  test("a fine pointer reveals on hover and hides on leave, not on click", () => {
    stubMedia({ fine: true });
    const { container } = render(<Landing2Page />);
    const root = container.querySelector(".landing2")!;
    expect(root.className).not.toContain("landing2-revealed");
    fireEvent.mouseEnter(root);
    expect(root.className).toContain("landing2-revealed");
    fireEvent.click(root);
    expect(root.className).toContain("landing2-revealed");
    fireEvent.mouseLeave(root);
    expect(root.className).not.toContain("landing2-revealed");
  });

  // Touch/coarse: tapping anywhere on the glass toggles.
  test("a coarse pointer toggles reveal on tap", () => {
    stubMedia({ fine: false });
    const { container } = render(<Landing2Page />);
    const root = container.querySelector(".landing2")!;
    expect(root.className).not.toContain("landing2-revealed");
    fireEvent.click(root);
    expect(root.className).toContain("landing2-revealed");
    fireEvent.click(root);
    expect(root.className).not.toContain("landing2-revealed");
  });

  // A tap that lands on an actual link must still navigate normally -- this
  // page's handler never calls preventDefault or stopPropagation, so the
  // click both reaches the browser's default action AND bubbles to the root.
  // The reveal toggling proves the second half: if a future edit added
  // stopPropagation to "protect" the link, this would catch it by the
  // toggle silently no longer happening on a link tap.
  test("a tap on a link inside the content layer still bubbles to the root", () => {
    stubMedia({ fine: false });
    render(<Landing2Page />);
    const root = document.querySelector(".landing2")!;
    const link = screen.getByText("Join the waitlist").closest("a")!;
    expect(root.className).not.toContain("landing2-revealed");
    const notPrevented = fireEvent.click(link);
    expect(root.className).toContain("landing2-revealed");
    // fireEvent.click returns false only when some handler called
    // preventDefault -- confirms the link's own default action (navigation)
    // was never blocked either.
    expect(notPrevented).toBe(true);
  });

  test("a coarse pointer never gets the hover handlers", () => {
    stubMedia({ fine: false });
    const { container } = render(<Landing2Page />);
    const root = container.querySelector(".landing2")!;
    fireEvent.mouseEnter(root);
    expect(root.className).not.toContain("landing2-revealed");
  });

  // The advisor's own bar for this test: under reduced motion, a shard must
  // never carry an inline transform, in either state -- not "transform:
  // none", genuinely absent, since a CSS @media override cannot win against
  // an inline style of the same property.
  test("reduced motion mounts without any transform styles, revealed or not", () => {
    stubMedia({ fine: true, reduced: true });
    const { container } = render(<Landing2Page />);
    const shards = container.querySelectorAll<HTMLElement>(".landing2-shard");
    expect(shards.length).toBeGreaterThan(0);
    shards.forEach((shard) => expect(shard.style.transform).toBe(""));

    fireEvent.mouseEnter(container.querySelector(".landing2")!);
    shards.forEach((shard) => expect(shard.style.transform).toBe(""));
  });

  test("ordinary motion sets a transform once revealed", () => {
    stubMedia({ fine: true, reduced: false });
    const { container } = render(<Landing2Page />);
    const root = container.querySelector(".landing2")!;
    const shard = container.querySelector<HTMLElement>(".landing2-shard")!;
    expect(shard.style.transform).toContain("translate(0px, 0px)");
    fireEvent.mouseEnter(root);
    expect(shard.style.transform).not.toContain("translate(0px, 0px)");
  });
});
