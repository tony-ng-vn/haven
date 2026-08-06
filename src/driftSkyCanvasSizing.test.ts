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
// duplicated). Landing2Page.tsx also hosts one (-> .landing2-sky), but it is
// NOT in this array: unlike these three, its width is deliberately not
// 100% (see its own describe block below, and its comment in index.css) --
// the box itself is sized to confine DriftSky's wander path to the navy
// zone, not just a full-width canvas hidden behind a mask, so it cannot
// share the 100%/100% check every other host class gets. A new FULL-WIDTH
// host class still belongs in this array in the same edit that creates it --
// the whole point of this file is that the bug does not get to wait for
// someone to notice a broken preview.
const DRIFTSKY_HOST_CLASSES = [".wl-sky", ".card-sky", ".landing-sky"] as const;

// The bare rule block for a single top-level class selector, e.g.
// ".wl-sky { ... }". Assumes (true for all three today) that the selector
// is not part of a comma-separated compound selector list, and that the
// first occurrence in the file is the one being asked for.
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

// .landing2-sky's own version of the same guard: the collapse-to-300x150
// bug this whole file exists to catch is about EXPLICIT sizing going
// missing, not specifically about that size being 100%. This page's canvas
// is deliberately narrower than its hero (see its own comment in index.css:
// the box confines DriftSky's wander path to the navy zone), so what has to
// hold here is that both the row-layout rule and its own narrow-layout
// override still give it an explicit, non-auto width and height -- never
// left to fall back to the replaced element's intrinsic size.
describe(".landing2-sky is confined on purpose, not collapsed by accident", () => {
  test("the row-layout rule: absolute, inset: 0, explicit width and height", () => {
    const rule = ruleFor(".landing2-sky");
    expect(rule, ".landing2-sky rule not found in index.css").not.toBe("");
    expect(rule).toMatch(/position:\s*absolute/);
    expect(rule).toMatch(/inset:\s*0/);
    expect(rule).toMatch(/width:\s*55%/);
    expect(rule).toMatch(/height:\s*100%/);
  });

  // A second, later rule block for the same selector, inside the narrow
  // layout's own media query -- ruleFor() only ever returns the FIRST match
  // in the file (the row-layout rule above), so this one is found the same
  // way but starting the search after that media query begins.
  test("the narrow-layout override: still an explicit, non-auto width and height", () => {
    const narrowSection = css.slice(css.indexOf("@media (max-width: 1279px)"));
    const rule = narrowSection.match(/\.landing2-sky\s*\{([^}]*)\}/)?.[1] ?? "";
    expect(rule, ".landing2-sky narrow-layout rule not found").not.toBe("");
    expect(rule).toMatch(/width:\s*100%/);
    expect(rule).toMatch(/height:\s*calc\(/);
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
