// The constellation lens: near the pointer, scattered stars join into a
// figure. That is the waitlist headline rendered as an interaction -- without
// Haven your people are scattered points, Haven is what connects them.
//
// Only the geometry lives here, pure and dependency-free, because it is the
// one part with logic worth testing. The drawing is in DriftSky.
// waitlist-design.md records why each number is what it is.

export const LENS = {
  radius: 195,
  // Fraction of the pointer gap closed each frame. Low enough that the lens
  // visibly trails the cursor instead of feeling stuck to it.
  lag: 0.055,
  // Where the fade starts, as a fraction of the radius. Below 1 the lens keeps
  // a bright plateau and dies out gradually, so it never shows an edge.
  softness: 0.85,
  zoom: 1.18,
  // Only the nearer, brighter stars join the figure. Faint background dust
  // would make it a web instead of a constellation.
  minStarSize: 0.95,
  // After this long without a pointer move the lens detaches and wanders, so a
  // phone (or an idle desktop) still sees the constellation form.
  idleMs: 2000,
} as const;

// Two slow sines per axis at incommensurate rates, so the path never visibly
// repeats and never reads as a loop. `time` is seconds.
export function wanderPoint(
  time: number,
  width: number,
  height: number,
): Point {
  return {
    x: width * (0.5 + 0.3 * Math.sin(time * 0.11) + 0.1 * Math.sin(time * 0.29)),
    y: height * (0.46 + 0.24 * Math.cos(time * 0.09) + 0.08 * Math.cos(time * 0.23)),
  };
}

export type Point = { x: number; y: number };

// 1 at the centre, 0 at the radius, never negative and never above 1.
export function falloff(distance: number, radius: number = LENS.radius): number {
  if (distance >= radius) return 0;
  const t = (1 - distance / radius) / LENS.softness;
  return t >= 1 ? 1 : t <= 0 ? 0 : t;
}

function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

// Push a point away from the lens centre. The slight swell is what makes the
// figure read as seen through something rather than drawn on top.
export function magnify(p: Point, centre: Point, zoom: number = LENS.zoom): Point {
  return {
    x: centre.x + (p.x - centre.x) * zoom,
    y: centre.y + (p.y - centre.y) * zoom,
  };
}

// The stars that make up the figure, in input order so the caller can pair each
// one with its magnified point. Measured against radius / zoom: a star at that
// distance lands exactly on the radius once magnified, and anything beyond it
// would be drawn at zero alpha anyway.
export function figureStars<T extends Point & { size: number }>(
  stars: readonly T[],
  centre: Point,
  radius: number = LENS.radius,
): T[] {
  const reach = radius / LENS.zoom;
  return stars.filter((s) => s.size > LENS.minStarSize && distance(s, centre) < reach);
}

// A line fades by its weaker end, so it never stops dead at an invisible
// boundary -- the whole reason the lens reads as a region of attention rather
// than a magnifying glass held over the page.
export function edgeAlpha(
  a: Point,
  b: Point,
  centre: Point,
  radius: number = LENS.radius,
): number {
  return Math.min(
    falloff(distance(a, centre), radius),
    falloff(distance(b, centre), radius),
  );
}
