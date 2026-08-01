import { describe, expect, test } from "vitest";
import {
  LANDING2_SEEDS,
  cellEdges,
  cellPolygon,
  centerRightScore,
  centroid,
  computeCells,
  edgeOpacity,
  frostyShardIndices,
  hashUnit,
  insetPolygon,
  junctionVertices,
  polygonArea,
  selectGlowDots,
  shardMaterial,
  shardMotion,
  sharedEdges,
  type Point,
} from "./landing2Geometry";

const VIEWPORT_AREA = 100 * 100;
const CORNERS: Point[] = [
  { x: 0, y: 0 },
  { x: 100, y: 0 },
  { x: 100, y: 100 },
  { x: 0, y: 100 },
];

function close(a: Point, b: Point, epsilon = 1e-6): boolean {
  return Math.abs(a.x - b.x) <= epsilon && Math.abs(a.y - b.y) <= epsilon;
}

describe("computeCells", () => {
  test("is deterministic: two computations agree exactly", () => {
    const a = computeCells(LANDING2_SEEDS);
    const b = computeCells(LANDING2_SEEDS);
    expect(a.length).toBe(b.length);
    a.forEach((cell, i) => {
      const pa = cellPolygon(cell);
      const pb = cellPolygon(b[i]);
      expect(pa.length).toBe(pb.length);
      pa.forEach((p, j) => expect(close(p, pb[j])).toBe(true));
    });
  });

  test("produces exactly one cell per seed", () => {
    const cells = computeCells(LANDING2_SEEDS);
    expect(cells.length).toBe(LANDING2_SEEDS.length);
    expect(cells.map((c) => c.seedIndex)).toEqual(LANDING2_SEEDS.map((_, i) => i));
  });

  test("every cell is a non-degenerate polygon", () => {
    const cells = computeCells(LANDING2_SEEDS);
    const MIN_AREA = 0.05; // viewport-percent^2; a sliver would fall well below this
    const areas = cells.map((cell) => polygonArea(cellPolygon(cell)));
    const minArea = Math.min(...areas);
    cells.forEach((cell, i) => {
      expect(cellPolygon(cell).length, `cell ${i} has too few vertices`).toBeGreaterThanOrEqual(3);
      expect(areas[i], `cell ${i} (seed ${JSON.stringify(cell.seed)}) area is degenerate`).toBeGreaterThan(
        MIN_AREA,
      );
    });
    // Surfaced for the report regardless of pass/fail: the smallest shard in
    // the fixed composition, and which seed produced it.
    const smallestIndex = areas.indexOf(minArea);
    console.log(
      `[landing2Geometry] smallest cell: seed ${smallestIndex} ${JSON.stringify(
        cells[smallestIndex].seed,
      )}, area ${minArea.toFixed(3)} (viewport-pct^2)`,
    );
  });

  test("every viewport corner falls inside exactly one cell", () => {
    const cells = computeCells(LANDING2_SEEDS);
    for (const corner of CORNERS) {
      const containing = cells.filter((cell) =>
        cellPolygon(cell).some((p) => close(p, corner, 1e-6)),
      );
      expect(containing.length, `corner ${JSON.stringify(corner)} should belong to exactly one cell`).toBe(
        1,
      );
    }
  });

  test("cell areas sum to the full viewport within 0.5%", () => {
    const cells = computeCells(LANDING2_SEEDS);
    const total = cells.reduce((sum, cell) => sum + polygonArea(cellPolygon(cell)), 0);
    expect(Math.abs(total - VIEWPORT_AREA) / VIEWPORT_AREA).toBeLessThan(0.005);
  });

  test("every interior edge is shared by exactly two cells, at coincident endpoints", () => {
    const cells = computeCells(LANDING2_SEEDS);
    const byTag = new Map<string, { from: Point; to: Point }[]>();
    for (const cell of cells) {
      for (const edge of cellEdges(cell)) {
        if (!edge.tag.startsWith("seed-pair:")) continue;
        const list = byTag.get(edge.tag) ?? [];
        list.push({ from: edge.from, to: edge.to });
        byTag.set(edge.tag, list);
      }
    }
    expect(byTag.size).toBeGreaterThan(0);
    for (const [tag, edges] of byTag) {
      expect(edges, `${tag} should be produced by exactly two cells`).toHaveLength(2);
      const [a, b] = edges;
      const sameDirection = close(a.from, b.from, 1e-6) && close(a.to, b.to, 1e-6);
      const reversed = close(a.from, b.to, 1e-6) && close(a.to, b.from, 1e-6);
      expect(sameDirection || reversed, `${tag}: the two cells computed different segments`).toBe(true);
    }
  });
});

describe("sharedEdges", () => {
  test("excludes boundary edges, keeps only seed-pair edges", () => {
    const cells = computeCells(LANDING2_SEEDS);
    const edges = sharedEdges(cells);
    expect(edges.length).toBeGreaterThan(0);
    edges.forEach((e) => expect(e.tag.startsWith("seed-pair:")).toBe(true));
  });
});

describe("junctionVertices", () => {
  test("finds at least one three-cell meeting point, all within the viewport", () => {
    const cells = computeCells(LANDING2_SEEDS);
    const junctions = junctionVertices(cells);
    expect(junctions.length).toBeGreaterThan(0);
    junctions.forEach((p) => {
      expect(p.x).toBeGreaterThanOrEqual(-1e-6);
      expect(p.x).toBeLessThanOrEqual(100 + 1e-6);
      expect(p.y).toBeGreaterThanOrEqual(-1e-6);
      expect(p.y).toBeLessThanOrEqual(100 + 1e-6);
    });
  });
});

describe("hashUnit", () => {
  test("is deterministic and stays within [0, 1)", () => {
    for (let i = 0; i < 30; i++) {
      const a = hashUnit(i);
      const b = hashUnit(i);
      expect(a).toBe(b);
      expect(a).toBeGreaterThanOrEqual(0);
      expect(a).toBeLessThan(1);
    }
  });

  test("varies across indices", () => {
    const values = new Set(Array.from({ length: 22 }, (_, i) => hashUnit(i)));
    expect(values.size).toBeGreaterThan(15);
  });
});

describe("shardMotion", () => {
  const cells = computeCells(LANDING2_SEEDS);

  test("drift direction points away from the composition centre", () => {
    cells.forEach((cell, i) => {
      const polygon = cellPolygon(cell);
      const c = centroid(polygon);
      const motion = shardMotion(polygon, i);
      // The unit vector should point the same general way as centroid-minus-centre.
      const towardX = c.x - 50;
      const towardY = c.y - 50;
      const dot = motion.dx * towardX + motion.dy * towardY;
      if (Math.hypot(towardX, towardY) > 1e-6) {
        expect(dot).toBeGreaterThanOrEqual(0);
      }
    });
  });

  // Widened from an original 10-22px after the owner's headless comparison
  // against the reference images: at that range shards thickened their
  // seams but never visibly separated. This is the one style-contract value
  // this file deliberately updates, per that brief.
  test("distance and rotation stay within the specified bounds", () => {
    cells.forEach((cell, i) => {
      const motion = shardMotion(cellPolygon(cell), i);
      expect(motion.distance).toBeGreaterThanOrEqual(26);
      expect(motion.distance).toBeLessThanOrEqual(48);
      expect(motion.rotationDeg).toBeGreaterThanOrEqual(-1.6);
      expect(motion.rotationDeg).toBeLessThanOrEqual(1.6);
      expect(motion.scale).toBeCloseTo(0.985, 5);
    });
  });

  test("is deterministic for a given polygon and index", () => {
    const polygon = cellPolygon(cells[5]);
    const a = shardMotion(polygon, 5);
    const b = shardMotion(polygon, 5);
    expect(a).toEqual(b);
  });
});

describe("centerRightScore", () => {
  test("prefers a point further right at the same height", () => {
    expect(centerRightScore({ x: 80, y: 50 })).toBeGreaterThan(
      centerRightScore({ x: 20, y: 50 }),
    );
  });

  test("prefers a point closer to vertical centre at the same x", () => {
    expect(centerRightScore({ x: 50, y: 50 })).toBeGreaterThan(
      centerRightScore({ x: 50, y: 5 }),
    );
  });
});

describe("selectGlowDots", () => {
  const cells = computeCells(LANDING2_SEEDS);
  const junctions = junctionVertices(cells);

  test("returns exactly the requested count, ranked by centerRightScore", () => {
    const picked = selectGlowDots(junctions, 10);
    expect(picked).toHaveLength(10);
    const scores = picked.map(centerRightScore);
    for (let i = 1; i < scores.length; i++) {
      expect(scores[i]).toBeLessThanOrEqual(scores[i - 1]);
    }
    // Every returned point is one of the actual junctions, not invented.
    picked.forEach((p) => expect(junctions.some((j) => j.x === p.x && j.y === p.y)).toBe(true));
  });

  test("never returns more than the vertices given", () => {
    expect(selectGlowDots(junctions, 1000)).toHaveLength(junctions.length);
  });
});

describe("shardMaterial", () => {
  test("is deterministic and stays within its documented ranges", () => {
    for (let i = 0; i < 22; i++) {
      const a = shardMaterial(i);
      const b = shardMaterial(i);
      expect(a).toEqual(b);
      expect(a.angleDeg).toBeGreaterThanOrEqual(0);
      expect(a.angleDeg).toBeLessThan(360);
      expect(a.lightnessT).toBeGreaterThanOrEqual(0);
      expect(a.lightnessT).toBeLessThanOrEqual(1);
      expect(a.restAlpha).toBeGreaterThanOrEqual(0.35);
      expect(a.restAlpha).toBeLessThanOrEqual(0.6);
    }
  });

  test("varies across shards rather than collapsing to one material", () => {
    const angles = new Set(Array.from({ length: 22 }, (_, i) => shardMaterial(i).angleDeg));
    expect(angles.size).toBeGreaterThan(15);
  });
});

describe("frostyShardIndices", () => {
  test("picks exactly 6 of 22, all valid indices, deterministically", () => {
    const a = frostyShardIndices(22);
    const b = frostyShardIndices(22);
    expect(a.size).toBe(6);
    expect(a).toEqual(b);
    for (const i of a) {
      expect(i).toBeGreaterThanOrEqual(0);
      expect(i).toBeLessThan(22);
    }
  });
});

describe("insetPolygon", () => {
  const cells = computeCells(LANDING2_SEEDS);
  const polygon = cellPolygon(cells[1]);

  test("factor 1 returns the polygon unchanged", () => {
    const same = insetPolygon(polygon, 1);
    polygon.forEach((p, i) => {
      expect(same[i].x).toBeCloseTo(p.x, 9);
      expect(same[i].y).toBeCloseTo(p.y, 9);
    });
  });

  test("a factor below 1 shrinks every vertex toward the centroid", () => {
    const c = centroid(polygon);
    const shrunk = insetPolygon(polygon, 0.9);
    polygon.forEach((p, i) => {
      const before = Math.hypot(p.x - c.x, p.y - c.y);
      const after = Math.hypot(shrunk[i].x - c.x, shrunk[i].y - c.y);
      expect(after).toBeLessThan(before);
    });
    // The centroid itself does not move -- it is a uniform scale about it.
    const shrunkCentroid = centroid(shrunk);
    expect(shrunkCentroid.x).toBeCloseTo(c.x, 6);
    expect(shrunkCentroid.y).toBeCloseTo(c.y, 6);
  });
});

describe("edgeOpacity", () => {
  test("stays within the documented range for every real seam", () => {
    const cells = computeCells(LANDING2_SEEDS);
    const edges = sharedEdges(cells);
    expect(edges.length).toBeGreaterThan(0);
    edges.forEach((edge) => {
      const o = edgeOpacity(edge);
      expect(o).toBeGreaterThanOrEqual(0.12);
      expect(o).toBeLessThanOrEqual(0.4);
    });
  });

  test("is deterministic for the same edge", () => {
    const cells = computeCells(LANDING2_SEEDS);
    const edge = sharedEdges(cells)[0];
    expect(edgeOpacity(edge)).toBe(edgeOpacity({ ...edge }));
  });
});
