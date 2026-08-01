import { describe, expect, test } from "vitest";
import {
  LANDING2_SEEDS,
  cellEdges,
  cellPolygon,
  centroid,
  computeCells,
  hashUnit,
  junctionVertices,
  polygonArea,
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

  test("distance and rotation stay within the specified bounds", () => {
    cells.forEach((cell, i) => {
      const motion = shardMotion(cellPolygon(cell), i);
      expect(motion.distance).toBeGreaterThanOrEqual(10);
      expect(motion.distance).toBeLessThanOrEqual(22);
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
