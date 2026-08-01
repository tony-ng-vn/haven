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
  // Finger follow must feel attached: desktop lag reads as breath, but on a
  // phone the same number makes the figure ignore the touch.
  touchLag: 0.28,
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
  // The fewest stars that still read as a figure rather than as a line or two.
  //
  // Star count is capped at 300, so past roughly 1400x900 density falls as the
  // window grows while the radius stays fixed: about 17 stars in the figure at
  // 1090x830, about 9 at 1800x1170, and a handful past 2560. Below this the
  // lens reaches further out rather than thinning, which is the fix
  // waitlist-design.md prescribes -- raising the star cap or dropping the
  // brightness threshold would change the sky on every screen instead of the
  // figure on the few that need it.
  minFigure: 7,
} as const;

// True for real fingers. Empty pointerType is treated as touch too: some
// WebViews omit the type, and those events must not get the mouse path
// (hover-follow without a press), or a tap sticks a lens forever.
export function isTouchPointer(pointerType: string): boolean {
  return pointerType === "touch" || pointerType === "";
}

// Whether DriftSky should attach the interactive pointer/touch listeners --
// including the non-passive touchmove that blocks page scroll under a drag.
// Split from "does the figure draw and wander at all" (lensOn) deliberately:
// the old full-page waitlist could afford that listener on every device
// because it was a fixed overlay with nothing to scroll. A page that scrolls
// normally cannot, so a coarse-pointer visitor gets the figure and its wander
// (see wanderPoint) but never the gesture that would fight their scroll --
// see LandingPage.tsx, which passes lens unconditionally and interactive only
// for a fine pointer.
export function gestureEnabled(input: {
  lensOn: boolean;
  interactive: boolean;
}): boolean {
  return input.lensOn && input.interactive;
}

export type Point = { x: number; y: number };

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

// The figure, and the radius its fade should use.
//
// The radius comes back because it is not always the one that went in. On a
// sky too sparse to fill the lens, the lens reaches out to the nearest
// qualifying stars instead of showing two of them, and the fade has to reach
// with it -- keeping the fixed radius would light stars whose edges then drew
// at zero alpha, which is the thinning it was meant to fix.
//
// The order is the input's, so the caller can still pair each star with its
// magnified point.
export function lensFigure<T extends Point & { size: number }>(
  stars: readonly T[],
  centre: Point,
  radius: number = LENS.radius,
): { stars: T[]; radius: number } {
  const inside = figureStars(stars, centre, radius);
  if (inside.length >= LENS.minFigure) return { stars: inside, radius };

  const qualifying = stars.filter((s) => s.size > LENS.minStarSize);
  // Nothing bright enough anywhere: an empty figure, and the radius it was
  // asked for, because there is no furthest star to measure one from.
  if (qualifying.length === 0) return { stars: [], radius };

  const nearest = [...qualifying]
    .sort((a, b) => distance(a, centre) - distance(b, centre))
    .slice(0, LENS.minFigure);
  const furthest = distance(nearest[nearest.length - 1], centre);
  const picked = new Set<T>(nearest);
  return {
    stars: stars.filter((s) => picked.has(s)),
    // Never smaller than the radius asked for: a dense sky that happens to
    // hold its stars close must not get a tighter lens than a sparse one.
    radius: Math.max(radius, furthest * LENS.zoom),
  };
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
