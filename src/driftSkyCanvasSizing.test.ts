import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

// The regression this pins: every CSS class that hosts a DriftSky canvas
// absolutely or fixed positioned with `inset: 0` must also declare explicit
// `width: 100%` and `height: 100%`.
//
// <canvas> is a replaced element (like <img>). For an absolutely or fixed
// positioned replaced element with width/height left auto, `inset: 0` alone
// does NOT stretch it to fill its containing block the way it would a <div>
// -- the box falls back to the canvas's intrinsic size (300x150 CSS px),
// anchored at the resolved top/left offset. This is exactly the bug that
// shipped on the landing hero: a 300x150 canvas pinned to the top-left corner
// of an otherwise empty viewport, ~12 stars (300*150/3600), the lens's own
// wander path (proportional to the canvas's measured width/height, see
// lens.ts's wanderPoint) compressed into that same tiny box -- which is
// exactly "one small constellation figure stuck in the top-left corner and
// an otherwise empty navy viewport" from the owner's report.
//
// Nothing about this fails loudly: the canvas still renders, still draws
// stars, still animates -- just onto ~12 stars in a box a few hundred pixels
// wide, wherever `inset: 0` happens to anchor a replaced element's intrinsic
// size. A future rule copy-pasting `position: absolute/fixed; inset: 0;`
// without the width/height lines would reintroduce this silently, so it is
// asserted here rather than left to be noticed on a deployed preview again.

const css = readFileSync("src/index.css", "utf8");

// Every class known to host a <DriftSky>. See App.tsx (SignIn -> .wl-sky),
// SkyPage.tsx / IosPage.tsx (-> .card-sky), and LandingPage.tsx /
// PolishedLandingPage.tsx (both -> .landing-sky, reused rather than
// duplicated). Landing2Page.tsx no longer hosts one at all: it was rebuilt
// around a real image (glass-hero.jpg) instead of a drawn sky, so .landing2-
// sky is gone, not renamed. A new host class belongs in this array in the
// same edit that creates it -- the whole point of this file is that the bug
// does not get to wait for someone to notice a broken preview.
const DRIFTSKY_HOST_CLASSES = [".wl-sky", ".card-sky", ".landing-sky"] as const;

// The bare rule block for a single top-level class selector, e.g.
// ".wl-sky { ... }". Assumes (true for all three today) that the selector
// is not part of a comma-separated compound selector list.
function ruleFor(selector: string): string {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = css.match(new RegExp(`${escaped}\\s*\\{([^}]*)\\}`));
  return match?.[1] ?? "";
}

describe("DriftSky canvas hosts stretch to fill their box", () => {
  test.each(DRIFTSKY_HOST_CLASSES)(
    "%s is positioned with inset: 0 AND carries explicit width/height",
    (selector) => {
      const rule = ruleFor(selector);
      expect(rule, `${selector} rule not found in index.css`).not.toBe("");
      // Guards the guard: if inset: 0 is ever dropped, this test would
      // otherwise pass on a rule that no longer needs the fix at all.
      expect(rule).toMatch(/inset:\s*0/);
      expect(rule).toMatch(/width:\s*100%/);
      expect(rule).toMatch(/height:\s*100%/);
    },
  );

  // The landing page's sky is the one of the three that must be fixed (a
  // page-wide background layer, not scoped to one section) rather than
  // absolute -- see LandingPage.tsx and the comment on .landing-sky.
  test(".landing-sky is fixed, not scoped to a scrolling ancestor", () => {
    expect(ruleFor(".landing-sky")).toMatch(/position:\s*fixed/);
  });
});

// The landing page's content sits on top of its own full-page fixed sky the
// same explicit way every other public page sits on top of .card-sky: a
// z-index: 0 background and a z-index: 1 (positioned) foreground on every
// section, not a negative z-index on the background alone. That second
// approach (paints behind ordinary static content with no z-index needed on
// the foreground, per the CSS2.1 painting order) was considered and rejected
// here: it depends on no ancestor between the canvas and its siblings ever
// acquiring its own stacking context, which is a fact about the whole page
// that is easy to invalidate by accident later. Pinned because it is the
// entire mechanism behind requirement (b) -- the sky showing through behind
// every section, not just the hero -- rendering cannot verify it in this
// test environment (happy-dom does not compute real layout/paint order).
describe("the landing page's content stacks above its fixed sky explicitly", () => {
  test(".landing-sky paints at z-index: 0, not a negative index", () => {
    expect(ruleFor(".landing-sky")).toMatch(/z-index:\s*0\b/);
  });

  test.each([".landing-hero", ".landing-section", ".site-footer"])(
    "%s is explicitly positioned above it (position + z-index: 1)",
    (selector) => {
      const rule = ruleFor(selector);
      expect(rule, `${selector} rule not found in index.css`).not.toBe("");
      expect(rule).toMatch(/position:\s*relative/);
      expect(rule).toMatch(/z-index:\s*1\b/);
    },
  );
});
