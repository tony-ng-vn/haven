import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { DriftSky } from "./DriftSky";
import {
  LANDING2_SEEDS,
  cellPolygon,
  computeCells,
  edgeOpacity,
  frostyShardIndices,
  hashUnit,
  insetPolygon,
  junctionVertices,
  selectGlowDots,
  shardMaterial,
  shardMotion,
  sharedEdges,
  type Point,
  type ShardMaterial,
} from "./landing2Geometry";

// inhavens.com/#/landing2, linked from nowhere.
//
// An experimental concept the owner is evaluating alongside the default
// landing: the whole viewport as one continuous pane of broken midnight-blue
// glass over a hidden memory world, at rest mostly assembled and only
// faintly suggesting what is beneath it, breathing apart on hover (desktop)
// or tap (touch) to reveal that world through the gaps. Not a card, not a
// demo panel -- the page itself is the glass, in three explicit layers (see
// index.css's landing2 section for the z-index each one paints at):
//   0 beneath -- the hidden memory world (sky, scenery, memory fragments)
//   1 glass   -- the shards, their seams, and the faint in-glass fragments
//   2 content -- the Sky and iPhone product copy, floating over the glass
// The shard geometry is a fixed, seeded Voronoi fracture (landing2Geometry.ts)
// -- the same 22 seeds every time, so the composition itself never drifts.
//
// No TopNav, no Footer: this concept is deliberately chromeless, and nothing
// on the site links here.
function prefersFinePointer(): boolean {
  return (
    typeof window !== "undefined" &&
    window.matchMedia("(hover: hover) and (pointer: fine)").matches
  );
}

function prefersReducedMotion(): boolean {
  return (
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches
  );
}

// The handwritten memory fragments in the beneath layer -- cursive, low
// opacity, each block a short run of lines at a fixed position and tilt.
const MEMORY_FRAGMENTS: Array<{
  x: number;
  y: number;
  rotation: number;
  lines: string[];
}> = [
  {
    x: 65,
    y: 50,
    rotation: -8,
    lines: ["that road trip", "summer 2018", "music loud", "windows down", "you, laughing"],
  },
  {
    x: 52,
    y: 90,
    rotation: 5,
    lines: ["london", "april 2019", "coffee and", "rainy walks"],
  },
];

// The two tilted "polaroid" vignettes: plain bordered rectangles holding a
// tiny abstract skyline/constellation stroke.
const POLAROIDS: Array<{ x: number; y: number; rotation: number }> = [
  { x: 47, y: 88, rotation: -4 },
  { x: 90, y: 85, rotation: 6 },
];

// ~24 tiny warm-gold particle dots scattered in the 45-75% x band. Computed
// once at module scope, not per render: hashUnit is a pure function of the
// index, so recomputing would only waste cycles for the identical result.
// Reuses .sky-tw (see PersonSky.tsx), the site's one twinkle mechanism --
// same reduced-motion override, no second animation system to keep in sync.
const PARTICLE_COUNT = 24;
const PARTICLES = Array.from({ length: PARTICLE_COUNT }, (_, i) => ({
  x: 45 + hashUnit(i * 7 + 1) * 30,
  y: 6 + hashUnit(i * 7 + 2) * 88,
  dur: 3 + hashUnit(i * 7 + 3) * 3,
  delay: -hashUnit(i * 7 + 4) * 4,
  hi: 0.55 + hashUnit(i * 7 + 5) * 0.25,
  lo: 0.12 + hashUnit(i * 7 + 6) * 0.12,
}));

// The faint in-glass fragments: sans, lowercase, positioned absolutely over
// the glass layer -- the "subtle memory fragments" from the owner's own
// reference prompt, kept atmospheric rather than readable UI copy.
const GLASS_FRAGMENTS: Array<{ text: string; x: number; y: number }> = [
  { text: "late night", x: 14, y: 8 },
  { text: "alex", x: 40, y: 10 },
  { text: "miss you", x: 62, y: 20 },
  { text: "good morning", x: 80, y: 42 },
  { text: "dinner", x: 41, y: 70 },
  { text: "mom", x: 84, y: 73 },
  { text: "be back soon", x: 60, y: 86 },
];

// 3 faint gold constellation mini-figures inside upper shards (small y), each
// a handful of points relative to its own anchor, echoing the brand's own
// lens figure in miniature. One anchored near [24,17] as asked; the other two
// placed in other upper-region seeds (seeds 6 and 7, at [55,6] and [72,10])
// so the flourish reads across the top of the composition, not just one spot.
const CONSTELLATION_FIGURES: Array<{ x: number; y: number; points: Array<[number, number]> }> = [
  { x: 24, y: 17, points: [[0, 0], [3, -2], [6, 1], [4, 4]] },
  { x: 58, y: 9, points: [[0, 1], [3, -1], [5, 2]] },
  { x: 78, y: 14, points: [[0, 0], [2.5, 2], [5, -0.5], [3, 3.5]] },
];

// Junction vertices are shared by three cells; ~10 get a small gold glow,
// chosen from the whole set by centerRightScore (see landing2Geometry.ts --
// shared with the seams' own brightness bias, so "brightest toward
// center-right" means the same thing in both places).
const GLOW_DOT_COUNT = 10;

function round(n: number): number {
  return Math.round(n * 100) / 100;
}

export function clipPathFor(polygon: Point[]): string {
  return `polygon(${polygon.map((p) => `${round(p.x)}% ${round(p.y)}%`).join(", ")})`;
}

function polygonPoints(polygon: readonly Point[]): string {
  return polygon.map((p) => `${round(p.x)},${round(p.y)}`).join(" ");
}

const SHARD_TRANSITION = "opacity 900ms cubic-bezier(.22,.61,.36,1)";
const SHARD_TRANSITION_WITH_TRANSFORM = `transform 900ms cubic-bezier(.22,.61,.36,1), ${SHARD_TRANSITION}`;

// Shard material: a per-shard two-tone gradient between a dark and a lighter
// navy-indigo base, angled per shard, so the glass reads as 22 distinct
// panes rather than one flat tint. lightnessT (from shardMaterial) picks
// where in that range this shard's own gradient centres; a small fixed
// spread around it is what gives each shard its own two-tone read.
const SHARD_DARK: readonly [number, number, number] = [38, 44, 84];
const SHARD_LIGHT: readonly [number, number, number] = [64, 72, 118];
const SHARD_LIGHTNESS_SPREAD = 0.22;

function mixChannel(a: number, b: number, t: number): number {
  return Math.round(a + (b - a) * t);
}

function mixRgb(t: number): [number, number, number] {
  return [
    mixChannel(SHARD_DARK[0], SHARD_LIGHT[0], t),
    mixChannel(SHARD_DARK[1], SHARD_LIGHT[1], t),
    mixChannel(SHARD_DARK[2], SHARD_LIGHT[2], t),
  ];
}

// The fill's own alpha is baked into these rgba() stops at material.restAlpha
// and never recomputed between rest and revealed -- see shardOpacity below
// for how the darker "glossy" revealed look is layered on top via a plain
// opacity multiplier instead, which is what makes it transitionable at all
// (a change in background-image/gradient stops does not animate smoothly).
//
// Exported for a direct string-content unit test: happy-dom's CSSStyleDeclaration
// cannot parse rgba() used inside a gradient function at all (confirmed by
// probing it directly -- a single-layer linear-gradient with rgba() stops
// alone comes back empty), so style.background is unreadable in jsdom-family
// test environments here. That is a test-tool limitation, not invalid CSS --
// real browsers render layered rgba() gradients correctly -- so the fix is
// testing this function's return value directly rather than reading it back
// through a DOM style object.
// No frost parameter: frost used to be an extra gradient layer baked into
// this same string, which meant it rode the shard's own opacity multiplier
// upward on reveal along with everything else -- exactly the reported bug
// (frosty shards reading as a brighter milky glare once revealed, when every
// other shard was darkening toward glossy). Frost is now a separate child
// element (.landing2-shard-frost) with its own opacity that scales DOWN on
// reveal, independent of this gradient's own opacity multiplier.
export function shardFillCss(material: ShardMaterial): string {
  const t0 = Math.max(0, material.lightnessT - SHARD_LIGHTNESS_SPREAD / 2);
  const t1 = Math.min(1, material.lightnessT + SHARD_LIGHTNESS_SPREAD / 2);
  const [r0, g0, b0] = mixRgb(t0);
  const [r1, g1, b1] = mixRgb(t1);
  const a = material.restAlpha.toFixed(2);
  const base = `linear-gradient(${round(material.angleDeg)}deg, rgba(${r0},${g0},${b0},${a}) 0%, rgba(${r1},${g1},${b1},${a}) 100%)`;
  const highlight = "radial-gradient(circle at 18% 14%, rgba(255,255,255,0.1), transparent 42%)";
  return `${highlight}, ${base}`;
}

// The alpha-multiplier trick: restAlpha is already baked into the gradient
// (shardFillCss), so a plain CSS opacity of 1 shows it exactly as-is. On
// reveal, the shard should darken by a fixed +0.08 of alpha regardless of
// its own restAlpha (0.35-0.6, per shard) -- the multiplier that adds a
// constant amount to a per-shard base is restAlpha+0.08 divided by
// restAlpha, computed per shard rather than one shared constant.
function shardOpacity(restAlpha: number, revealed: boolean): number {
  return revealed ? (restAlpha + 0.08) / restAlpha : 1;
}

// Seams double in brightness on reveal (per edge, since edgeOpacity is
// per-edge already), capped so the brightest edges do not blow out past a
// believable seam glow.
function seamOpacity(rest: number, revealed: boolean): number {
  return revealed ? Math.min(rest * 2, 0.85) : rest;
}

function SkyGlyph() {
  return (
    <svg className="landing2-glyph" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <circle cx="4" cy="16" r="1.4" fill="var(--accent)" />
      <circle cx="11" cy="6" r="1.6" fill="var(--accent)" />
      <circle cx="19" cy="11" r="1.3" fill="var(--accent)" />
      <circle cx="15" cy="19" r="1.1" fill="var(--accent)" />
      <path
        d="M4 16 L11 6 L19 11 L15 19 L11 6"
        fill="none"
        stroke="var(--accent)"
        strokeWidth="0.8"
        opacity="0.7"
      />
    </svg>
  );
}

function IphoneGlyph() {
  return (
    <svg className="landing2-glyph" viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <rect x="2.5" y="2.5" width="19" height="19" rx="6" fill="none" stroke="var(--accent)" strokeWidth="1.2" />
      <circle cx="9" cy="15" r="1.3" fill="var(--accent)" />
      <circle cx="16" cy="9" r="1.3" fill="var(--accent)" />
      <line x1="9" y1="15" x2="16" y2="9" stroke="var(--accent)" strokeWidth="0.8" opacity="0.7" />
    </svg>
  );
}

export function Landing2Page() {
  // Read once at mount, like LandingPage's own prefersFinePointer: neither a
  // device's pointer type nor its motion preference changes mid-session, and
  // reading once keeps the reveal mechanism (hover vs tap) and the transform
  // omission below simple and stable for the page's lifetime.
  const [coarse] = useState(() => !prefersFinePointer());
  const [reducedMotion] = useState(prefersReducedMotion);
  const [revealed, setRevealed] = useState(false);

  useEffect(() => {
    document.title = "Haven - Landing 2";
  }, []);

  const cells = useMemo(() => computeCells(LANDING2_SEEDS), []);
  const edges = useMemo(() => sharedEdges(cells), [cells]);
  const glowDots = useMemo(
    () => selectGlowDots(junctionVertices(cells), GLOW_DOT_COUNT),
    [cells],
  );
  const frostySet = useMemo(() => frostyShardIndices(cells.length), [cells]);

  // Coarse pointers toggle on tap; nothing here calls preventDefault, so a
  // tap that lands on a link or button still navigates or activates exactly
  // as it would anywhere else -- the toggle just also happens alongside it.
  const handleTap = coarse ? () => setRevealed((r) => !r) : undefined;
  // Fine pointers reveal for as long as the pointer rests anywhere on the
  // page. mouseenter/mouseleave (not mouseover/mouseout) only fire when the
  // pointer crosses the ROOT's own boundary, never when it moves between the
  // root and a descendant -- so hovering an interactive element inside the
  // content layer needs no special-casing at all.
  const handleEnter = !coarse ? () => setRevealed(true) : undefined;
  const handleLeave = !coarse ? () => setRevealed(false) : undefined;

  return (
    <div
      className={`landing2${revealed ? " landing2-revealed" : ""}`}
      onClick={handleTap}
      onMouseEnter={handleEnter}
      onMouseLeave={handleLeave}
    >
      {/* Beneath layer, z 0: the hidden memory world. */}
      <div className="landing2-beneath">
        <DriftSky className="landing2-sky" />

        <svg
          className="landing2-scene"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          <defs>
            {/* Peak alphas well under the seams' revealed range (edgeOpacity
                doubled, capped at 0.85) -- the water reads as scenery behind
                the glass, never brighter than the glass itself. A soft ramp
                (not a hard 0% stop) is what "softens the top edge against
                the mountain base": the band eases in rather than snapping to
                full strength exactly at the ridge line. */}
            <linearGradient id="landing2-water" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--dusk)" stopOpacity="0.06" />
              <stop offset="22%" stopColor="var(--dusk)" stopOpacity="0.22" />
              <stop offset="100%" stopColor="var(--dusk)" stopOpacity="0" />
            </linearGradient>
            <linearGradient id="landing2-water-shimmer" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#f2efe9" stopOpacity="0.04" />
              <stop offset="22%" stopColor="#f2efe9" stopOpacity="0.16" />
              <stop offset="100%" stopColor="#f2efe9" stopOpacity="0" />
            </linearGradient>
            {/* A small, tight specular highlight aligned under the moon
                (cx 62) rather than a second uniform band -- a moonlit water
                reflection is a glint, not an even wash. */}
            <radialGradient id="landing2-water-specular" cx="0.5" cy="0.35" r="0.6">
              <stop offset="0%" stopColor="#f2efe9" stopOpacity="0.38" />
              <stop offset="100%" stopColor="#f2efe9" stopOpacity="0" />
            </radialGradient>
            {/* The mask below reads LUMINANCE, not alpha -- these stops must
                stay white (full luminance at stop-opacity 1, computed as
                black i.e. masked-out at stop-opacity 0). Swapping the stop
                color would silently change the mask's own strength. */}
            <linearGradient id="landing2-water-fade-x" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0%" stopColor="#fff" stopOpacity="0" />
              <stop offset="16%" stopColor="#fff" stopOpacity="1" />
              <stop offset="84%" stopColor="#fff" stopOpacity="1" />
              <stop offset="100%" stopColor="#fff" stopOpacity="0" />
            </linearGradient>
            {/* Mask content matches the masked group's own bounds exactly, so
                the mask element's default -10%/+10% region (relative to that
                same bounding box) comfortably contains it -- same margin-past-
                bounds reasoning as the seam blur filter's explicit region,
                just satisfied here by construction instead of by an override.
                "The masked group's bounds" is the union of every child inside
                the <g mask=...> below (both water rects AND the specular
                ellipse), which today all fall within x 35-75 / y 30-40 -- if
                a future edit ever widens or moves the specular ellipse past
                that box, this rect needs to grow with it, or the newly
                exposed area renders as masked-out (black = hidden) rather
                than passed through. */}
            <mask id="landing2-water-mask" maskContentUnits="userSpaceOnUse">
              <rect x="35" y="30" width="40" height="10" fill="url(#landing2-water-fade-x)" />
            </mask>
            <radialGradient id="landing2-window">
              <stop offset="0%" stopColor="#ffd9a0" stopOpacity="0.95" />
              <stop offset="100%" stopColor="#ffd9a0" stopOpacity="0" />
            </radialGradient>
            <radialGradient id="landing2-window-bloom">
              <stop offset="0%" stopColor="#ffd9a0" stopOpacity="0.75" />
              <stop offset="100%" stopColor="#ffd9a0" stopOpacity="0" />
            </radialGradient>
          </defs>

          {/* crescent moon, ~62,12 -- pale grey at rest, warm gold revealed
              (.landing2-moon-disc), nested in the scene-el opacity fade */}
          <g className="landing2-scene-el">
            <circle cx="62" cy="12" r="3.2" className="landing2-moon-disc" />
            <circle cx="63.3" cy="11.2" r="3.2" fill="var(--night)" />
          </g>

          {/* Two mountain ridges, 35-75% x at 15-30% y, lightened indigo
              stepped by ridge (front lighter/closer, back darker/further) so
              they register instead of reading as near-black on near-black.
              A moonlit rim on the top ridge only, and the water band --
              masked to fade its left/right ends and contained to exactly the
              ridges' own 35-75% width, so it reads as reflection under the
              scenery rather than a floating rectangle. */}
          <g className="landing2-scene-el">
            <polygon points="35,29 44,18 54,25 65,16 75,28 75,32 35,32" fill="var(--dusk)" />
            <polygon points="35,31 47,23 60,28 75,30 75,32 35,32" fill="#171c3a" opacity="0.95" />
            <polyline
              className="landing2-mountain-rim"
              points="35,29 44,18 54,25 65,16 75,28"
              fill="none"
            />
            <g mask="url(#landing2-water-mask)">
              <rect x="35" y="30" width="40" height="10" fill="url(#landing2-water)" />
              <rect
                className="landing2-water-shimmer"
                x="35"
                y="30"
                width="40"
                height="10"
                fill="url(#landing2-water-shimmer)"
              />
              <ellipse
                className="landing2-water-shimmer"
                cx="62"
                cy="34"
                rx="9"
                ry="3.5"
                fill="url(#landing2-water-specular)"
              />
            </g>
          </g>

          {/* tree silhouette cluster, lower-center-left, one glowing window
              with a bloom halo that only appears on reveal */}
          <g className="landing2-scene-el">
            <polygon points="40,80 42,67 44.4,80" fill="#0b0d1e" />
            <polygon points="43,80 45.6,66 48.2,80" fill="#0b0d1e" />
            <polygon points="46.2,80 48.8,68.5 51.4,80" fill="#0b0d1e" />
            <circle className="landing2-window-bloom" cx="45.6" cy="75" r="2.6" fill="url(#landing2-window-bloom)" />
            <circle cx="45.6" cy="75" r="0.9" fill="url(#landing2-window)" />
          </g>

          {/* Left-edge foliage, tall enough to actually enter the frame (the
              previous pass's cluster topped out around y 62-64 and did not
              register in a capture) -- five varying-height silhouettes from
              y 30 to y 85, within the leftmost 12% of the viewport, sitting
              behind the copy's shards like the rest of the beneath layer. */}
          <g className="landing2-scene-el">
            <polygon points="0.8,85 2,58 3.2,85" fill="#0b0d1e" />
            <polygon points="2.6,85 4.4,42 6.2,85" fill="#0b0d1e" />
            <polygon points="5,85 7,30 9,85" fill="#0b0d1e" />
            <polygon points="7.6,85 9.2,50 10.8,85" fill="#0b0d1e" />
            <polygon points="9.4,85 10.8,65 12,85" fill="#0b0d1e" />
            <circle className="landing2-window-bloom" cx="6.5" cy="68" r="1.8" fill="url(#landing2-window-bloom)" />
            <circle cx="6.5" cy="68" r="0.6" fill="url(#landing2-window)" />
          </g>
        </svg>

        {MEMORY_FRAGMENTS.map((block, i) => (
          <div
            key={i}
            className="landing2-memory landing2-scene-el"
            style={{
              left: `${block.x}%`,
              top: `${block.y}%`,
              transform: `translate(-50%, -50%) rotate(${block.rotation}deg)`,
            }}
          >
            {block.lines.map((line, j) => (
              <div key={j}>{line}</div>
            ))}
          </div>
        ))}

        {POLAROIDS.map((p, i) => (
          <div
            key={i}
            className="landing2-polaroid landing2-scene-el"
            style={{
              left: `${p.x}%`,
              top: `${p.y}%`,
              transform: `translate(-50%, -50%) rotate(${p.rotation}deg)`,
            }}
          >
            <svg viewBox="0 0 40 30" aria-hidden="true">
              <polyline
                points="4,22 12,10 20,18 28,6 36,16"
                fill="none"
                stroke="var(--accent)"
                strokeWidth="1"
                opacity="0.6"
              />
              <circle cx="12" cy="10" r="1" fill="var(--accent)" />
              <circle cx="28" cy="6" r="1" fill="var(--accent)" />
            </svg>
          </div>
        ))}

        <svg
          className="landing2-particles"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          {PARTICLES.map((particle, i) => {
            // Brighter twinkle band once revealed, capped well short of 1 so
            // they stay particles, not new stars.
            const hi = revealed ? Math.min(particle.hi + 0.15, 0.95) : particle.hi;
            const lo = revealed ? Math.min(particle.lo + 0.12, 0.4) : particle.lo;
            const style: CSSProperties = {
              "--d": `${particle.dur.toFixed(1)}s`,
              "--dl": `${particle.delay.toFixed(1)}s`,
              "--hi": hi.toFixed(2),
              "--lo": lo.toFixed(2),
            } as CSSProperties;
            if (!reducedMotion) {
              // A small per-particle drift, direction from its own hash so it
              // is stable across renders -- "a few px", not a flight path.
              const angle = hashUnit(i * 5 + 2) * Math.PI * 2;
              style.transform = revealed
                ? `translate(${round(Math.cos(angle) * 0.3)}px, ${round(Math.sin(angle) * 0.3)}px)`
                : "translate(0px, 0px)";
              style.transition = "transform 900ms cubic-bezier(.22,.61,.36,1)";
            }
            return (
              <circle
                key={i}
                className="sky-tw"
                cx={particle.x}
                cy={particle.y}
                r={0.35}
                fill="var(--accent)"
                style={style}
              />
            );
          })}
        </svg>

        <div className="landing2-veil" />
      </div>

      {/* Glass layer, z 1: the shards, their seams, and the in-glass text. */}
      <div className="landing2-glass">
        {cells.map((cell) => {
          const polygon = cellPolygon(cell);
          const motion = shardMotion(polygon, cell.seedIndex);
          const material = shardMaterial(cell.seedIndex);
          const frosty = frostySet.has(cell.seedIndex);
          const style: CSSProperties = {
            clipPath: clipPathFor(polygon),
            background: shardFillCss(material),
            // Opacity is set here, in both branches below, not just the
            // transform one: reduced motion keeps every brightness/opacity
            // half of the reveal, only the movement drops out.
            opacity: shardOpacity(material.restAlpha, revealed),
          };
          if (!reducedMotion) {
            style.transform = revealed
              ? `translate(${round(motion.dx * motion.distance)}px, ${round(
                  motion.dy * motion.distance,
                )}px) rotate(${round(motion.rotationDeg)}deg) scale(${motion.scale})`
              : "translate(0px, 0px) rotate(0deg) scale(1)";
            style.transition = SHARD_TRANSITION_WITH_TRANSFORM;
          } else {
            // No transform at all under reduced motion -- the reveal is a
            // pure crossfade of opacity and color (the fill's own gradient
            // stops never change; only the opacity multiplier above does).
            style.transition = SHARD_TRANSITION;
          }
          return (
            <div key={cell.seedIndex} className="landing2-shard" style={style}>
              {/* Inherits the parent's clip-path (clip-path clips the whole
                  rendered subtree, not just the element it's set on), so this
                  needs no clip-path of its own. Its own opacity -- a plain
                  CSS class toggle, not inline -- scales the frost tint DOWN
                  on reveal, independent of the shard's own opacity above. */}
              {frosty && <div className="landing2-shard-frost" />}
            </div>
          );
        })}

        <svg
          className="landing2-seams"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          <defs>
            <radialGradient id="landing2-glow">
              <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.9" />
              <stop offset="100%" stopColor="var(--accent)" stopOpacity="0" />
            </radialGradient>
            {/* One global light direction, one gradient: applied to every
                shard's rim via objectBoundingBox units (the default), so it
                independently reruns upper-left-to-lower-right across each
                shard's own bounding box rather than needing 22 copies. */}
            <linearGradient id="landing2-rim" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stopColor="#dfe8f7" stopOpacity="0.9" />
              <stop offset="100%" stopColor="#dfe8f7" stopOpacity="0" />
            </linearGradient>
            {/* Filter region widened past the element's own bounding box --
                the default -10%/+10% clips a blurred seam that runs near the
                viewport edge, and applying this once to the whole group
                (rather than per line) computes the region once, not 44
                times. */}
            <filter id="landing2-seam-blur-filter" x="-30%" y="-30%" width="160%" height="160%">
              <feGaussianBlur stdDeviation="0.35" />
            </filter>
          </defs>

          {/* Inner bevel rim, one inset polygon per shard, all sharing the
              one light-direction gradient above. Drawn under the seam lines
              so a crisp seam still reads as the brighter of the two. */}
          {cells.map((cell) => (
            <polygon
              key={cell.seedIndex}
              className="landing2-rim"
              points={polygonPoints(insetPolygon(cellPolygon(cell), 0.94))}
              fill="none"
            />
          ))}

          {/* Blurred duplicate of every seam, painted before the crisp lines
              so the bloom sits underneath them. */}
          <g className="landing2-seam-blur" filter="url(#landing2-seam-blur-filter)">
            {edges.map((edge, i) => (
              <line key={i} x1={edge.from.x} y1={edge.from.y} x2={edge.to.x} y2={edge.to.y} />
            ))}
          </g>

          {edges.map((edge, i) => (
            <line
              key={i}
              className="landing2-seam-line"
              x1={edge.from.x}
              y1={edge.from.y}
              x2={edge.to.x}
              y2={edge.to.y}
              style={{ opacity: seamOpacity(edgeOpacity(edge), revealed) }}
            />
          ))}

          {/* Junction glow: a soft halo under a small bright core, both
              scaled by rank -- glowDots is already sorted center-right-first
              by selectGlowDots, so the earliest (most center-right) dots
              read as the brightest. */}
          {glowDots.map((v, i) => {
            const strength = 1 - (i / Math.max(glowDots.length - 1, 1)) * 0.4;
            return (
              <g key={i}>
                <circle cx={v.x} cy={v.y} r={0.9 * strength} fill="url(#landing2-glow)" opacity={strength} />
                <circle cx={v.x} cy={v.y} r={0.32 * strength} fill="var(--accent)" opacity={0.9 * strength} />
              </g>
            );
          })}

          {CONSTELLATION_FIGURES.map((figure, i) => (
            <g key={i} className="landing2-mini-figure">
              <polyline
                points={figure.points.map(([dx, dy]) => `${figure.x + dx},${figure.y + dy}`).join(" ")}
                fill="none"
              />
              {figure.points.map(([dx, dy], j) => (
                <circle key={j} cx={figure.x + dx} cy={figure.y + dy} r={0.4} />
              ))}
            </g>
          ))}
        </svg>

        {GLASS_FRAGMENTS.map((f, i) => (
          <span
            key={i}
            className="landing2-fragment"
            style={{ left: `${f.x}%`, top: `${f.y}%` }}
          >
            {f.text}
          </span>
        ))}
      </div>

      {/* Content layer, z 2: the product copy, over the two calm large cells. */}
      <div className="landing2-content">
        <div className="landing2-copy landing2-copy-sky">
          <SkyGlyph />
          <h2 className="landing2-eyebrow">YOUR SKY, FOR MAC</h2>
          <p className="landing2-body">
            Your Sky reads your own iMessage history and Contacts locally on
            your Mac, and draws everyone you actually talk to as a map you
            can explore.
          </p>
          <a
            className="landing2-pill"
            href="/demo-sky.html"
            target="_blank"
            rel="noopener noreferrer"
          >
            Explore a sample sky
          </a>
          <p className="landing2-caption">A sample sky, invented people.</p>
          {/* Verbatim from the reference, deliberately not reconciled with the
              default landing's hero CTA ("Sky app, coming soon") -- the owner
              is resolving that tension directly, not this page. */}
          <a className="sky-download" href="#/sky">
            Get Your Sky for Mac
          </a>
        </div>

        <div className="landing2-copy landing2-copy-iphone">
          <IphoneGlyph />
          <h2 className="landing2-eyebrow">HAVEN, FOR IPHONE</h2>
          <p className="landing2-body">
            Connect with someone in one tap, and find them again later by any
            detail you remember. Haven for iPhone is still in development.
          </p>
          <a className="landing2-pill" href="#/ios">
            Join the waitlist
          </a>
        </div>
      </div>
    </div>
  );
}
