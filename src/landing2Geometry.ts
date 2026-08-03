// The shard geometry behind the "landing page 2" glass concept (#/landing2,
// unlinked -- see Landing2Page.tsx). A seeded Voronoi diagram over the
// viewport, computed by half-plane clipping: each seed's cell is the
// [0,100]x[0,100] rectangle, clipped successively by the perpendicular
// bisector against every other seed. With n around 22 that is a trivial
// O(n^2) amount of work, and it gives cells with exactly matching shared
// edges by construction -- there is no separate "snap the seams to the
// shards" step, because the seam IS a piece of each shard's own boundary.
//
// Pure and dependency-free, like lens.ts, because the geometry is the one
// part of this page worth unit testing on its own.

export type Point = { x: number; y: number };

// The composition's fixed art direction. Do not add, remove, or reorder --
// see Landing2Page.tsx's doc comment for why these are locked.
export const LANDING2_SEEDS: readonly Point[] = [
  { x: 18, y: 22 },
  { x: 33, y: 45 },
  { x: 16, y: 80 },
  { x: 5, y: 38 },
  { x: 6, y: 64 },
  { x: 35, y: 8 },
  { x: 55, y: 6 },
  { x: 72, y: 10 },
  { x: 90, y: 8 },
  { x: 52, y: 28 },
  { x: 60, y: 50 },
  { x: 52, y: 68 },
  { x: 66, y: 72 },
  { x: 74, y: 38 },
  { x: 82, y: 55 },
  { x: 88, y: 30 },
  { x: 93, y: 50 },
  { x: 92, y: 72 },
  { x: 78, y: 88 },
  { x: 58, y: 88 },
  { x: 40, y: 90 },
  { x: 27, y: 92 },
];

const VIEWPORT: readonly Point[] = [
  { x: 0, y: 0 },
  { x: 100, y: 0 },
  { x: 100, y: 100 },
  { x: 0, y: 100 },
];

// A vertex tagged with the constraint that produced the edge LEAVING it (to
// the next vertex in the polygon, wrapping around). "boundary" for the four
// original viewport edges; "seed-pair:i-j" (i < j) for an edge on the
// perpendicular bisector of seeds i and j -- canonical regardless of which
// cell computed it, so a cell's edge and its neighbor's copy of the same
// edge carry the identical tag.
type TaggedVertex = Point & { edgeTagAfter: string };

function pairTag(i: number, j: number): string {
  return `seed-pair:${Math.min(i, j)}-${Math.max(i, j)}`;
}

// clip(p) <= 0 keeps the half-plane closer to `keep` than `other` (their
// shared bisector is clip(p) == 0). Derived from |p-keep|^2 < |p-other|^2.
function halfPlane(keep: Point, other: Point) {
  const a = 2 * (other.x - keep.x);
  const b = 2 * (other.y - keep.y);
  const c = other.x * other.x + other.y * other.y - keep.x * keep.x - keep.y * keep.y;
  return (p: Point) => a * p.x + b * p.y - c;
}

const EPS = 1e-9;

// Sutherland-Hodgman against one half-plane, carrying edge tags through:
// a surviving (possibly shortened) edge keeps its original tag; the new
// "capping" edge introduced where the clip cuts the polygon is tagged
// `capTag`. Polygons here are always convex (an intersection of half-planes),
// so a single clip introduces at most one capping edge -- there is no case
// where the same tag needs to appear twice in one cell's output.
function clip(vertices: TaggedVertex[], f: (p: Point) => number, capTag: string): TaggedVertex[] {
  const inside = (p: Point) => f(p) <= EPS;
  const output: TaggedVertex[] = [];
  const n = vertices.length;
  for (let i = 0; i < n; i++) {
    const curr = vertices[i];
    const next = vertices[(i + 1) % n];
    const currIn = inside(curr);
    const nextIn = inside(next);
    if (currIn) {
      output.push(curr);
      if (!nextIn) {
        const t = f(curr) / (f(curr) - f(next));
        output.push({
          x: curr.x + t * (next.x - curr.x),
          y: curr.y + t * (next.y - curr.y),
          edgeTagAfter: capTag,
        });
      }
    } else if (nextIn) {
      const t = f(curr) / (f(curr) - f(next));
      output.push({
        x: curr.x + t * (next.x - curr.x),
        y: curr.y + t * (next.y - curr.y),
        edgeTagAfter: curr.edgeTagAfter,
      });
    }
  }
  return output;
}

export type Cell = {
  seedIndex: number;
  seed: Point;
  vertices: TaggedVertex[];
};

// One cell per seed: the seed's Voronoi region, clipped to the viewport.
export function computeCells(seeds: readonly Point[]): Cell[] {
  return seeds.map((seed, i) => {
    let vertices: TaggedVertex[] = VIEWPORT.map((p) => ({ ...p, edgeTagAfter: "boundary" }));
    seeds.forEach((other, j) => {
      if (j === i) return;
      vertices = clip(vertices, halfPlane(seed, other), pairTag(i, j));
    });
    return { seedIndex: i, seed, vertices };
  });
}

// Plain point ring, for a clip-path polygon or a filled shape -- callers that
// do not care which constraint produced which edge.
export function cellPolygon(cell: Cell): Point[] {
  return cell.vertices.map(({ x, y }) => ({ x, y }));
}

export type TaggedEdge = { from: Point; to: Point; tag: string };

// A cell's edges in traversal order, each carrying the tag of the constraint
// that bounds it.
export function cellEdges(cell: Cell): TaggedEdge[] {
  const n = cell.vertices.length;
  return cell.vertices.map((v, i) => ({
    from: { x: v.x, y: v.y },
    to: { x: cell.vertices[(i + 1) % n].x, y: cell.vertices[(i + 1) % n].y },
    tag: v.edgeTagAfter,
  }));
}

export function polygonArea(points: readonly Point[]): number {
  let sum = 0;
  for (let i = 0; i < points.length; i++) {
    const a = points[i];
    const b = points[(i + 1) % points.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return Math.abs(sum) / 2;
}

// The internal (seed-pair) shared edges, one representative per tag -- the
// cracks the seam SVG draws. Boundary edges (the fracture meeting the edge of
// the screen) are excluded: they are not shared by two cells, so there is
// nothing to seam there.
export function sharedEdges(cells: readonly Cell[]): TaggedEdge[] {
  const seen = new Map<string, TaggedEdge>();
  for (const cell of cells) {
    for (const edge of cellEdges(cell)) {
      if (!edge.tag.startsWith("seed-pair:")) continue;
      if (!seen.has(edge.tag)) seen.set(edge.tag, edge);
    }
  }
  return [...seen.values()];
}

function close(a: Point, b: Point, epsilon = 1e-6): boolean {
  return Math.abs(a.x - b.x) <= epsilon && Math.abs(a.y - b.y) <= epsilon;
}

// Points where three (or more) cells meet: endpoints touched by two or more
// different shared edges. A shared edge's other endpoint -- where the crack
// simply runs off the edge of the screen -- touches only one shared edge and
// is excluded. Deduped by proximity, since the same vertex is reported by
// each of the (typically three) cells that meet there.
export function junctionVertices(cells: readonly Cell[]): Point[] {
  const edges = sharedEdges(cells);
  const junctions: Point[] = [];
  const endpoints = edges.flatMap((e) => [e.from, e.to]);
  for (const p of endpoints) {
    const touching = endpoints.filter((q) => close(q, p, 1e-4)).length;
    // Each of the (typically 3) edges meeting here contributes this point as
    // one of its own two endpoints, so a true junction is touched 3+ times
    // across the flattened endpoint list -- 2+ is used as a safe floor.
    if (touching >= 3 && !junctions.some((j) => close(j, p, 1e-4))) {
      junctions.push(p);
    }
  }
  return junctions;
}

// A small deterministic hash, so per-shard motion (which direction it drifts,
// how much it rotates) is stable across renders and across loads without
// storing any state -- the shard index is the only input.
export function hashUnit(seed: number): number {
  const x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453;
  return x - Math.floor(x);
}

export type ShardMotion = {
  // Unit vector from the composition centre [50,50] to the cell's centroid.
  dx: number;
  dy: number;
  // How far along that vector the shard drifts when revealed, in viewport
  // percentage points (small; this is glass breathing apart, not flying).
  distance: number;
  rotationDeg: number;
  scale: number;
};

const CENTRE: Point = { x: 50, y: 50 };

export function centroid(points: readonly Point[]): Point {
  let x = 0;
  let y = 0;
  for (const p of points) {
    x += p.x;
    y += p.y;
  }
  return { x: x / points.length, y: y / points.length };
}

// The revealed-state motion for one shard, entirely derived from its polygon
// and index -- no per-shard art direction to keep in sync by hand.
//
// Distance range widened from an original 10-22px: at that range the shards
// thickened their seams but did not visibly separate, so the "dark openings
// between shards" the composition depends on never read as openings.
export function shardMotion(polygon: readonly Point[], shardIndex: number): ShardMotion {
  const c = centroid(polygon);
  const dist = Math.hypot(c.x - CENTRE.x, c.y - CENTRE.y);
  const dx = dist > EPS ? (c.x - CENTRE.x) / dist : 0;
  const dy = dist > EPS ? (c.y - CENTRE.y) / dist : 0;
  // Furthest cell centroid from centre, across the fixed seed set, sets the
  // top of the range -- roughly the [90,8]/[92,72] corner seeds.
  const maxDist = 55;
  const t = Math.min(dist / maxDist, 1);
  const distance = 26 + t * (48 - 26);
  const rotationDeg = (hashUnit(shardIndex) * 2 - 1) * 1.6;
  const scale = 0.985;
  return { dx, dy, distance, rotationDeg, scale };
}

// Favors the center-right of the composition (centre x=50): a higher x
// scores better, softened near the very top/bottom edges where a bright
// point would sit too close to the frame. Shared by junction-dot selection
// and per-edge seam brightness, so "brightest toward center-right" means the
// same thing in both places rather than two independently-tuned biases.
export function centerRightScore(p: Point): number {
  return p.x - Math.abs(p.y - 50) * 0.3;
}

// The ~10 (or however many are asked for) junction vertices that get a gold
// glow, chosen from the whole set by centerRightScore rather than every
// junction glowing equally.
export function selectGlowDots(vertices: readonly Point[], count: number): Point[] {
  return [...vertices]
    .sort((a, b) => centerRightScore(b) - centerRightScore(a))
    .slice(0, count);
}

// Per-shard "material": a deterministic gradient axis and lightness so the
// glass reads as a patchwork of distinct panes -- 22 shards with the same
// flat tint read as a diagram, not glass.
export type ShardMaterial = {
  angleDeg: number;
  // Where in the base-to-light range this shard's own two-tone gradient
  // centres -- 0 sits toward the darker end, 1 toward the lighter end.
  lightnessT: number;
  // The gradient's own baked-in alpha at rest, 0.35-0.6. Kept baked into the
  // fill rather than applied as a separate CSS opacity so the fill itself
  // never needs to be re-computed between rest and revealed -- only a
  // multiplier on top of it changes (see Landing2Page.tsx's shardOpacity).
  restAlpha: number;
};

export function shardMaterial(shardIndex: number): ShardMaterial {
  const angleDeg = hashUnit(shardIndex * 13 + 3) * 360;
  const lightnessT = hashUnit(shardIndex * 13 + 5);
  const restAlpha = 0.35 + hashUnit(shardIndex * 13 + 9) * 0.25;
  return { angleDeg, lightnessT, restAlpha };
}

// Exactly 6 of the shards read frostier (a whiter cast) -- picked by ranking
// a hash score rather than rolling each shard independently, so the count is
// guaranteed rather than merely likely across a set this small.
const FROSTY_COUNT = 6;

export function frostyShardIndices(shardCount: number): Set<number> {
  const scored = Array.from({ length: shardCount }, (_, i) => ({
    i,
    score: hashUnit(i * 13 + 11),
  }));
  scored.sort((a, b) => b.score - a.score);
  return new Set(scored.slice(0, FROSTY_COUNT).map((s) => s.i));
}

// A polygon shrunk toward its own centroid by `factor` (e.g. 0.94 for a 6%
// inset) -- the rim's "inset duplicate of the shard's own boundary" rather
// than an exact overlay of the seam lines, which would fight them visually.
export function insetPolygon(polygon: readonly Point[], factor: number): Point[] {
  const c = centroid(polygon);
  return polygon.map((p) => ({
    x: c.x + (p.x - c.x) * factor,
    y: c.y + (p.y - c.y) * factor,
  }));
}

// "seed-pair:i-j" -> [i, j], or null for a boundary edge (which edgeOpacity
// never sees, since sharedEdges already excludes those).
function parsePairIndices(tag: string): [number, number] | null {
  const match = /^seed-pair:(\d+)-(\d+)$/.exec(tag);
  if (match === null) return null;
  return [Number(match[1]), Number(match[2])];
}

// A per-edge rest opacity in [0.12, 0.4]: 60% the edge's own hash, 40% the
// same center-right bias as the junction dots, so the brightest seams are
// varied but still cluster toward center-right rather than being uniformly
// random across the composition.
export function edgeOpacity(edge: TaggedEdge): number {
  const parsed = parsePairIndices(edge.tag);
  const hashSeed = parsed !== null ? parsed[0] * 1000 + parsed[1] : 0;
  const mid = { x: (edge.from.x + edge.to.x) / 2, y: (edge.from.y + edge.to.y) / 2 };
  // centerRightScore spans roughly -35..65 across this composition; folded
  // into 0..1 for blending against the hash term.
  const positionT = Math.min(Math.max((centerRightScore(mid) + 35) / 100, 0), 1);
  const hashT = hashUnit(hashSeed * 7 + 17);
  const t = hashT * 0.6 + positionT * 0.4;
  return 0.12 + t * (0.4 - 0.12);
}
