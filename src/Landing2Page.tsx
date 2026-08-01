import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { DriftSky } from "./DriftSky";
import {
  LANDING2_SEEDS,
  cellPolygon,
  computeCells,
  hashUnit,
  junctionVertices,
  shardMotion,
  sharedEdges,
  type Point,
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
// chosen from the whole set by a center-right bias (composition centre is
// x=50, so this simply prefers a higher x, softened near the very top/bottom
// edges where a glow would sit too close to the frame).
const GLOW_DOT_COUNT = 10;

// Named rather than inlined into the sort: verified equivalent to the
// previous inline expression (both reduce to score(b) - score(a)), but a
// three-term subtraction chain is exactly the kind of thing that reads as a
// sign error even when it is not one -- not worth that ambiguity in a
// comparator nobody will re-derive from memory later.
function centerRightScore(p: Point): number {
  return p.x - Math.abs(p.y - 50) * 0.3;
}

export function selectGlowDots(vertices: Point[], count: number): Point[] {
  return [...vertices]
    .sort((a, b) => centerRightScore(b) - centerRightScore(a))
    .slice(0, count);
}

function round(n: number): number {
  return Math.round(n * 100) / 100;
}

export function clipPathFor(polygon: Point[]): string {
  return `polygon(${polygon.map((p) => `${round(p.x)}% ${round(p.y)}%`).join(", ")})`;
}

const SHARD_TRANSITION = "opacity 900ms cubic-bezier(.22,.61,.36,1)";
const SHARD_TRANSITION_WITH_TRANSFORM = `transform 900ms cubic-bezier(.22,.61,.36,1), ${SHARD_TRANSITION}`;

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
            <linearGradient id="landing2-water" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#232a4d" stopOpacity="0.55" />
              <stop offset="100%" stopColor="#232a4d" stopOpacity="0" />
            </linearGradient>
            <radialGradient id="landing2-window">
              <stop offset="0%" stopColor="#ffd9a0" stopOpacity="0.95" />
              <stop offset="100%" stopColor="#ffd9a0" stopOpacity="0" />
            </radialGradient>
          </defs>

          {/* crescent moon, ~62,12 */}
          <circle cx="62" cy="12" r="3.2" fill="#f2e7d5" opacity="0.9" />
          <circle cx="63.3" cy="11.2" r="3.2" fill="var(--night)" />

          {/* two mountain ridges, 35-75% x at 15-30% y, near-black indigo */}
          <polygon points="35,29 44,18 54,25 65,16 75,28 75,32 35,32" fill="#141936" />
          <polygon points="35,31 47,23 60,28 75,30 75,32 35,32" fill="#0c0e20" opacity="0.92" />
          {/* water reflection band directly below the ridges */}
          <rect x="35" y="32" width="40" height="7" fill="url(#landing2-water)" />

          {/* tree silhouette cluster, lower-center-left, one glowing window */}
          <polygon points="40,80 42,67 44.4,80" fill="#0b0d1e" />
          <polygon points="43,80 45.6,66 48.2,80" fill="#0b0d1e" />
          <polygon points="46.2,80 48.8,68.5 51.4,80" fill="#0b0d1e" />
          <circle cx="45.6" cy="75" r="0.9" fill="url(#landing2-window)" />
        </svg>

        {MEMORY_FRAGMENTS.map((block, i) => (
          <div
            key={i}
            className="landing2-memory"
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
            className="landing2-polaroid"
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
          {PARTICLES.map((particle, i) => (
            <circle
              key={i}
              className="sky-tw"
              cx={particle.x}
              cy={particle.y}
              r={0.35}
              fill="var(--accent)"
              style={
                {
                  "--d": `${particle.dur.toFixed(1)}s`,
                  "--dl": `${particle.delay.toFixed(1)}s`,
                  "--hi": particle.hi.toFixed(2),
                  "--lo": particle.lo.toFixed(2),
                } as CSSProperties
              }
            />
          ))}
        </svg>

        <div className="landing2-veil" />
      </div>

      {/* Glass layer, z 1: the shards, their seams, and the in-glass text. */}
      <div className="landing2-glass">
        {cells.map((cell) => {
          const polygon = cellPolygon(cell);
          const motion = shardMotion(polygon, cell.seedIndex);
          const style: CSSProperties = { clipPath: clipPathFor(polygon) };
          if (!reducedMotion) {
            style.transform = revealed
              ? `translate(${round(motion.dx * motion.distance)}px, ${round(
                  motion.dy * motion.distance,
                )}px) rotate(${round(motion.rotationDeg)}deg) scale(${motion.scale})`
              : "translate(0px, 0px) rotate(0deg) scale(1)";
            style.transition = SHARD_TRANSITION_WITH_TRANSFORM;
          } else {
            // No transform at all under reduced motion -- the reveal is a
            // pure opacity crossfade (opacity itself comes from the shared
            // .landing2-shard / .landing2-revealed rule, not inline).
            style.transition = SHARD_TRANSITION;
          }
          return <div key={cell.seedIndex} className="landing2-shard" style={style} />;
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
          </defs>

          {edges.map((edge, i) => (
            <line
              key={i}
              className="landing2-seam-line"
              x1={edge.from.x}
              y1={edge.from.y}
              x2={edge.to.x}
              y2={edge.to.y}
            />
          ))}

          {glowDots.map((v, i) => (
            <circle key={i} cx={v.x} cy={v.y} r={0.5} fill="url(#landing2-glow)" />
          ))}

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
