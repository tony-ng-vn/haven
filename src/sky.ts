// The Deep Field sky: every person's card is a unique patch of space,
// minted deterministically from their identity. Same person, same sky,
// forever. Pure and dependency-free so it stays trivially testable.

export type SkyStar = {
  x: number;
  y: number;
  r: number;
  hi: number; // resting opacity
  lo: number; // twinkle-low opacity
  dur: number; // twinkle duration seconds
  delay: number;
  rvd: number; // 0..1 reveal stagger seed: when this star ignites
};

export type SkyMajor = SkyStar & { hue: number };

export type SkyData = {
  width: number;
  height: number;
  pad: number;
  hues: [number, number, number];
  nebulae: Array<{ cx: number; cy: number; rx: number; ry: number; hue: number; alpha: number }>;
  minors: SkyStar[];
  giants: SkyMajor[];
  majors: SkyMajor[];
  edges: Array<[number, number]>;
  flares: Array<{ x: number; y: number; len: number; dur: number; delay: number }>;
  shoot: { x1: number; y1: number; x2: number; y2: number; delay: number };
};

const W = 384;
const H = 560;
const PAD = 34;
const MIN_SEPARATION = 68;
const MINOR_COUNT = 150;

function hashString(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

// mulberry32: tiny, fast, deterministic.
function seededRandom(seed: number): () => number {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function personHues(name: string, handle?: string): [number, number, number] {
  const h = hashString(name + (handle ?? ""));
  // Unsigned shifts: a signed >> on a large hash yields negative hues.
  return [h % 360, (h >>> 9) % 360, (h >>> 18) % 360];
}

// Rejection-sampled star placement: nothing crowds, nothing clips, and the
// figure keeps to the upper sky so the name owns the bottom of the card.
function placeMajors(rand: () => number, count: number): Array<{ x: number; y: number }> {
  const points: Array<{ x: number; y: number }> = [];
  let tries = 0;
  while (points.length < count && tries < 600) {
    tries++;
    const x = PAD + rand() * (W - PAD * 2);
    const y = PAD + rand() * (H * 0.62 - PAD);
    const crowded = points.some((p) => {
      const dx = p.x - x;
      const dy = p.y - y;
      return dx * dx + dy * dy < MIN_SEPARATION * MIN_SEPARATION;
    });
    if (!crowded) points.push({ x, y });
  }
  return points;
}

// Prim's minimum spanning tree: each star joins its nearest branch, which is
// why real star charts look calm instead of criss-crossed.
function spanningTree(points: Array<{ x: number; y: number }>): Array<[number, number]> {
  const inTree = [0];
  const edges: Array<[number, number]> = [];
  while (inTree.length < points.length) {
    let best: { i: number; j: number; d: number } | null = null;
    for (const i of inTree) {
      for (let j = 0; j < points.length; j++) {
        if (inTree.includes(j)) continue;
        const dx = points[i].x - points[j].x;
        const dy = points[i].y - points[j].y;
        const d = dx * dx + dy * dy;
        if (best === null || d < best.d) best = { i, j, d };
      }
    }
    if (best === null) break;
    edges.push([best.i, best.j]);
    inTree.push(best.j);
  }
  return edges;
}

export function buildSky(name: string, handle?: string): SkyData {
  const rand = seededRandom(hashString(name + (handle ?? "")));
  const hues = personHues(name, handle);

  const nebulae = [
    { cx: W * 0.35, cy: H * 0.25, rx: W * 0.75, ry: H * 0.42, hue: hues[0], alpha: 0.18 },
    { cx: W * 0.75, cy: H * 0.5, rx: W * 0.65, ry: H * 0.36, hue: hues[1], alpha: 0.15 },
    { cx: W * 0.4, cy: H * 0.7, rx: W * 0.6, ry: H * 0.3, hue: hues[2], alpha: 0.13 },
  ];

  // Depth: many faint stars on a power law -- the difference between a
  // diagram and a sky.
  const minors: SkyStar[] = [];
  for (let i = 0; i < MINOR_COUNT; i++) {
    const hi = 0.25 + rand() * 0.55;
    minors.push({
      x: rand() * W,
      y: rand() * H,
      r: 0.4 + Math.pow(rand(), 2.6) * 1.4,
      hi,
      lo: Math.max(0.08, hi - 0.3),
      dur: 2.6 + rand() * 4.5,
      delay: rand() * 6,
      rvd: rand(),
    });
  }

  // A few colored giants, like a telescope frame.
  const giants: SkyMajor[] = [];
  for (let i = 0; i < 5; i++) {
    giants.push({
      x: PAD + rand() * (W - PAD * 2),
      y: PAD + rand() * (H * 0.8),
      r: 1.2 + rand(),
      hue: hues[i % 3],
      hi: 0.9,
      lo: 0.5,
      dur: 3 + rand() * 3,
      delay: rand() * 4,
      rvd: rand(),
    });
  }

  const placed = placeMajors(rand, 7 + Math.floor(rand() * 2));
  const edges = spanningTree(placed);
  const majors: SkyMajor[] = placed.map((p, i) => ({
    x: p.x,
    y: p.y,
    r: 1.5 + rand() * 1.9,
    hue: hues[i % 3],
    hi: 1,
    lo: 0.62,
    dur: 3 + rand() * 3.4,
    delay: rand() * 5,
    rvd: rand(),
  }));

  // The two brightest stars in the figure earn diffraction flares.
  const byBrightness = majors
    .map((m, i) => ({ r: m.r, i }))
    .sort((a, b) => b.r - a.r)
    .slice(0, 2);
  const flares = byBrightness.map(({ r, i }) => ({
    x: majors[i].x,
    y: majors[i].y,
    len: r * 9,
    dur: 4 + rand() * 3,
    delay: rand() * 4,
  }));

  const sx = 40 + rand() * 160;
  const sy = 30 + rand() * 120;
  const shoot = { x1: sx, y1: sy, x2: sx - 34, y2: sy - 19, delay: 3 + rand() * 8 };

  return { width: W, height: H, pad: PAD, hues, nebulae, minors, giants, majors, edges, flares, shoot };
}

// -------------------------------------------------------------- atlas home

export type ClusterStar = { x: number; y: number; r: number; hue: number };

export type ClusterData = {
  width: number;
  height: number;
  stars: ClusterStar[];
  edges: Array<[number, number]>;
};

// A person's constellation shrunk to a map cluster. It reuses buildSky's
// majors + edges so the figure on the atlas is recognizably the SAME shape as
// on their card and detail sky -- identity, not decoration. Minors are dropped;
// the shared dust field carries the faint-star texture instead.
export function buildCluster(
  name: string,
  handle?: string,
  opts?: { width?: number; height?: number; pad?: number },
): ClusterData {
  const width = opts?.width ?? 120;
  const height = opts?.height ?? 92;
  const pad = opts?.pad ?? 8;
  const sky = buildSky(name, handle);

  const xs = sky.majors.map((m) => m.x);
  const ys = sky.majors.map((m) => m.y);
  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);
  // Guard the degenerate single-column/row case so we never divide by zero.
  const spanX = maxX - minX || 1;
  const spanY = maxY - minY || 1;
  const innerW = Math.max(0, width - pad * 2);
  const innerH = Math.max(0, height - pad * 2);

  const stars: ClusterStar[] = sky.majors.map((m) => ({
    x: pad + ((m.x - minX) / spanX) * innerW,
    y: pad + ((m.y - minY) / spanY) * innerH,
    // Map the card radius (~1.5..3.4) into a small, readable map radius.
    r: 1.1 + (m.r - 1.5) * 0.5,
    hue: m.hue,
  }));

  return { width, height, stars, edges: sky.edges };
}

export type DustStar = {
  x: number; // unit coords in [0,1], scaled to the viewport by the caller
  y: number;
  r: number;
  hi: number;
  lo: number;
  dur: number;
  delay: number;
};

// One shared field of faint background stars behind every cluster -- seeded
// from a fixed string, NOT per person, so the whole sky twinkles as one. Unit
// coordinates keep it resolution-independent across resizes.
export function buildDust(count = 80, seed = "euno-atlas-dust"): DustStar[] {
  const rand = seededRandom(hashString(seed));
  const dust: DustStar[] = [];
  for (let i = 0; i < count; i++) {
    dust.push({
      x: rand(),
      y: rand(),
      r: 0.4 + rand() * 0.7,
      // Deliberately dim: dust must never compete with a person's stars.
      hi: 0.18 + rand() * 0.16,
      lo: 0.06 + rand() * 0.06,
      dur: 3 + rand() * 4,
      delay: rand() * 4,
    });
  }
  return dust;
}

// Golden-angle spiral placement, ordered by the recent-first query: index 0
// (newest) sits nearest the center, each later person spirals outward. The y
// radius is squashed so the field reads as a wide sky rather than a disc.
// maxR is capped so the outermost cluster's full box + label never leaves the
// viewport -- the layout, not the caller, owns staying in bounds.
export function atlasLayout(
  count: number,
  width: number,
  height: number,
  opts?: {
    boxW?: number;
    boxH?: number;
    labelH?: number;
    centerYOffset?: number;
  },
): Array<{ x: number; y: number }> {
  const boxW = opts?.boxW ?? 120;
  const boxH = opts?.boxH ?? 92;
  const labelH = opts?.labelH ?? 46;
  const centerYOffset = opts?.centerYOffset ?? 14;

  const cx = width / 2;
  const cy = height / 2 + centerYOffset;
  const squash = 0.82;

  // Room the outermost cluster needs on each side (label only hangs below).
  const marginX = boxW / 2 + 8;
  const marginTop = boxH / 2 + 8;
  const marginBottom = boxH / 2 + labelH + 8;

  const maxRx = Math.min(cx - marginX, width - cx - marginX);
  const maxRy = Math.min(cy - marginTop, height - cy - marginBottom) / squash;
  const maxR = Math.max(0, Math.min(maxRx, maxRy, Math.min(width, height) * 0.42));

  const n = Math.max(count, 1);
  const points: Array<{ x: number; y: number }> = [];
  for (let i = 0; i < count; i++) {
    const angle = i * 2.399963; // golden angle in radians
    const rad = maxR * Math.sqrt((i + 0.7) / n);
    points.push({
      x: cx + Math.cos(angle) * rad,
      y: cy + Math.sin(angle) * rad * squash,
    });
  }
  return points;
}
