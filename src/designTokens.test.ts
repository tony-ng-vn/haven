import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

// The web mirror of ios/HavenTests/DesignTokenTests.swift. Haven's palette,
// type rule, and motion timings are defined once, in the iOS design files
// (HavenColor.swift, HavenFont.swift, HavenMotion.swift), and the web must
// track them by value -- nothing imports across the platform boundary, so
// drift is silent until someone puts the two apps side by side. These tests
// pin the CSS to the committed dusk palette so a stray Apple-default blue or
// a light-theme token cannot come back without failing loudly.

const css = readFileSync("src/index.css", "utf8");

// The committed dusk palette, from HavenColor.swift. This list is closed.
const dusk = {
  night: "#0e1123",
  duskRaised: "#232a4d",
  ember: "#e8a87c",
  star: "#ffd9a0",
  ink: "#f2efe9",
  muted: "#9da3be",
  faint: "#767c9c",
  cream: "#f2e7d5",
  creamInk: "#1a1730",
};

describe("dusk palette tokens", () => {
  test("the token block carries the committed palette", () => {
    expect(css).toContain(`--night: ${dusk.night}`);
    expect(css).toContain(`--text: ${dusk.ink}`);
    expect(css).toContain(`--muted: ${dusk.muted}`);
    expect(css).toContain(`--faint: ${dusk.faint}`);
    expect(css).toContain(`--accent: ${dusk.star}`);
    expect(css).toContain(`--accent-fill: ${dusk.cream}`);
    expect(css).toContain(`--accent-fill-text: ${dusk.creamInk}`);
    // hairline and fill are white opacities, not hues (HavenColor's rule).
    expect(css).toContain("--border: rgba(255, 255, 255, 0.1)");
    expect(css).toContain("--field-bg: rgba(255, 255, 255, 0.06)");
  });

  test("the Apple-default palette is gone", () => {
    // The pre-design-system chrome: Apple store grays and system blues.
    for (const banned of [
      "#0071e3",
      "#0a84ff",
      "#178bff",
      "#f5f5f7",
      "245, 245, 247",
      "#1d1d1f",
      "#1c1c1e",
      "#6e6e73",
      "#98989d",
      "#b8b8bd",
    ]) {
      expect(css, `index.css still carries ${banned}`).not.toContain(banned);
    }
  });

  test("the app is dark-only, like iOS", () => {
    expect(css).toContain("color-scheme: dark");
    // No second palette behind a media query: one theme, absolute values.
    expect(css).not.toContain("prefers-color-scheme");
  });

  test("the ground is the iOS NightBackground, not flat black", () => {
    // Night base, dusk rising from the bottom, ember at the horizon.
    expect(css).toContain(`--dusk: ${dusk.duskRaised}`);
    expect(css).toMatch(/35, 42, 77/); // dusk in the body gradient
    expect(css).toMatch(/232, 168, 124/); // ember glow
    // iOS Safari ignores fixed attachment; without these two the gradient
    // tiles a short page into stacked dusk bands.
    expect(css).toMatch(/background-repeat: no-repeat/);
  });
});

describe("type rule", () => {
  test("serif is reserved for people's names", () => {
    // THE RULE from HavenFont.swift: serif is what sets a person apart from
    // the interface. One token, one grouped rule.
    expect(css).toMatch(/--font-serif:\s*ui-serif/);
    const nameRule = css.match(
      /\.person-name,[^{]*\.triage-name,[^{]*\.atlas-cluster-name,[^{]*\.card-name[^{]*\{[^}]*font-family: var\(--font-serif\)/,
    );
    expect(nameRule, "grouped person-name serif rule missing").not.toBeNull();
    // Exclusivity, the web version of "a grep for serif outside this file
    // should return nothing": exactly two rules use the serif -- the name
    // rule and the public pages' editorial rule. A third use anywhere is a
    // deliberate decision, not a drive-by; raise this count with it.
    const uses = css.match(/font-family: var\(--font-serif\)/g) ?? [];
    expect(uses).toHaveLength(2);
  });
});

describe("motion", () => {
  test("durations track HavenMotion", () => {
    expect(css).toContain("--t-fast: 140ms"); // pressDuration
    expect(css).toContain("--t-screen: 240ms"); // screenDuration
    expect(css).not.toContain("--t-screen: 260ms");
  });
});

describe("focus", () => {
  test("composite pills carry the ring, not their inner inputs", () => {
    // A text input matches :focus-visible even on pointer focus, so the
    // global ring painted a hard rectangle inside the rounded glass pills.
    expect(css).toMatch(
      /\.atlas-input:focus-visible[^{]*\{[^}]*box-shadow: none/,
    );
    expect(css).toContain(".atlas-pill:focus-within");
    expect(css).toContain(".meet-input-row:focus-within");
  });
});

describe("browser chrome", () => {
  test("theme-color wears the night", () => {
    // The tab bar and installed-app chrome are the first pixels anyone sees.
    const html = readFileSync("index.html", "utf8");
    const manifest = readFileSync("public/manifest.webmanifest", "utf8");
    expect(html).toContain('name="theme-color" content="#0e1123"');
    expect(html).not.toContain("#f5f5f7");
    expect(manifest).toContain('"theme_color": "#0e1123"');
  });
});

describe("component sources", () => {
  test("no component hardcodes the retired blues", () => {
    const banned = /#0071e3|#0a84ff|#178bff|10,\s*132,\s*255/i;
    const files = readdirSync("src").filter(
      (name) => /\.(ts|tsx)$/.test(name) && !name.includes(".test."),
    );
    for (const name of files) {
      const source = readFileSync(join("src", name), "utf8");
      expect(banned.test(source), `${name} carries a retired blue`).toBe(false);
    }
  });
});
