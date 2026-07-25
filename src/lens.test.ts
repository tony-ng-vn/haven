import { describe, expect, test } from "vitest";
import {
  LENS,
  edgeAlpha,
  falloff,
  figureStars,
  isTouchPointer,
  magnify,
  wanderPoint,
} from "./lens";
import { spanningTree } from "./sky";

const CENTRE = { x: 100, y: 100 };

function star(x: number, y: number, size: number) {
  return { x, y, size };
}

describe("falloff", () => {
  test("is full at the centre and nothing at the radius", () => {
    expect(falloff(0)).toBe(1);
    expect(falloff(LENS.radius)).toBe(0);
    expect(falloff(LENS.radius + 50)).toBe(0);
  });

  test("stays within 0 and 1 and never rises with distance", () => {
    let previous = falloff(0);
    for (let d = 0; d <= LENS.radius + 20; d += 5) {
      const value = falloff(d);
      expect(value).toBeGreaterThanOrEqual(0);
      expect(value).toBeLessThanOrEqual(1);
      expect(value).toBeLessThanOrEqual(previous);
      previous = value;
    }
  });

  test("softness holds the centre at full brightness well past the middle", () => {
    // The plateau is what hides the edge: a linear fade would already be at
    // 0.75 here, and the lens would read as a disc with a rim.
    expect(falloff(LENS.radius * 0.1)).toBe(1);
    expect(falloff(LENS.radius * 0.5)).toBeLessThan(1);
  });

  test("honors a caller-supplied radius", () => {
    expect(falloff(60, 50)).toBe(0);
    expect(falloff(0, 50)).toBe(1);
  });
});

describe("magnify", () => {
  test("leaves the centre where it is", () => {
    expect(magnify(CENTRE, CENTRE)).toEqual(CENTRE);
  });

  test("pushes a point outward by the zoom factor", () => {
    const p = magnify({ x: 200, y: 100 }, CENTRE);
    expect(p.x).toBeCloseTo(100 + 100 * LENS.zoom);
    expect(p.y).toBeCloseTo(100);
  });

  test("keeps the direction and scales the distance", () => {
    const p = magnify({ x: 40, y: 220 }, CENTRE);
    const before = Math.hypot(40 - 100, 220 - 100);
    const after = Math.hypot(p.x - 100, p.y - 100);
    expect(after).toBeCloseTo(before * LENS.zoom);
    expect(p.x).toBeLessThan(CENTRE.x);
    expect(p.y).toBeGreaterThan(CENTRE.y);
  });
});

describe("figureStars", () => {
  test("takes only the near, bright stars", () => {
    const stars = [
      star(100, 100, 1.6), // dead centre, bright
      star(100, 300, 1.6), // past radius / zoom
      star(110, 110, 0.6), // near but too faint to join a figure
    ];
    expect(figureStars(stars, CENTRE)).toEqual([stars[0]]);
  });

  test("admits stars up to the magnified radius, not the raw one", () => {
    // A star drawn at radius / zoom lands exactly on the radius once magnified,
    // so anything further contributes nothing but cost.
    const edge = LENS.radius / LENS.zoom;
    const inside = star(100 + edge - 1, 100, 1.6);
    const outside = star(100 + edge + 1, 100, 1.6);
    expect(figureStars([inside, outside], CENTRE)).toEqual([inside]);
  });

  test("returns nothing when the lens sits on empty sky", () => {
    expect(figureStars([star(900, 900, 1.6)], CENTRE)).toEqual([]);
  });

  test("preserves input order so callers can pair stars with their points", () => {
    const stars = [star(60, 100, 1.2), star(100, 100, 1.8), star(140, 100, 1.0)];
    expect(figureStars(stars, CENTRE)).toEqual(stars);
  });
});

describe("edgeAlpha", () => {
  test("fades a line by its weaker end", () => {
    const near = { x: 100, y: 100 };
    const far = { x: 100 + LENS.radius * 0.9, y: 100 };
    expect(edgeAlpha(near, far, CENTRE)).toBeCloseTo(falloff(LENS.radius * 0.9));
  });

  test("is symmetric", () => {
    const a = { x: 130, y: 100 };
    const b = { x: 100, y: 250 };
    expect(edgeAlpha(a, b, CENTRE)).toBeCloseTo(edgeAlpha(b, a, CENTRE));
  });

  test("goes dark when either end leaves the lens", () => {
    const inside = { x: 100, y: 100 };
    const outside = { x: 100 + LENS.radius + 10, y: 100 };
    expect(edgeAlpha(inside, outside, CENTRE)).toBe(0);
  });
});

describe("isTouchPointer", () => {
  test("treats touch and blank types as fingers", () => {
    expect(isTouchPointer("touch")).toBe(true);
    expect(isTouchPointer("")).toBe(true);
    expect(isTouchPointer("mouse")).toBe(false);
    expect(isTouchPointer("pen")).toBe(false);
  });
});

describe("wanderPoint", () => {
  test("stays inside the sky", () => {
    for (let t = 0; t < 40; t += 0.5) {
      const p = wanderPoint(t, 1000, 800);
      expect(p.x).toBeGreaterThan(0);
      expect(p.x).toBeLessThan(1000);
      expect(p.y).toBeGreaterThan(0);
      expect(p.y).toBeLessThan(800);
    }
  });

  test("moves over time instead of sitting still", () => {
    const a = wanderPoint(0, 1000, 800);
    const b = wanderPoint(3, 1000, 800);
    expect(Math.hypot(a.x - b.x, a.y - b.y)).toBeGreaterThan(10);
  });
});

describe("the figure", () => {
  test("connects every chosen star exactly once", () => {
    const stars = [
      star(100, 100, 1.6),
      star(140, 120, 1.4),
      star(70, 150, 1.2),
      star(120, 60, 1.5),
    ];
    const chosen = figureStars(stars, CENTRE);
    const points = chosen.map((s) => magnify(s, CENTRE));
    const edges = spanningTree(points);
    // A spanning tree over n points has n - 1 edges, which is what keeps the
    // figure reading as a constellation rather than a web.
    expect(edges).toHaveLength(points.length - 1);
    const touched = new Set(edges.flat());
    expect(touched.size).toBe(points.length);
  });

  test("draws no line for a lone star", () => {
    const points = [{ x: 100, y: 100 }];
    expect(spanningTree(points)).toEqual([]);
  });
});
