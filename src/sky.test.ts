import { describe, expect, test } from "vitest";
import {
  atlasLayout,
  buildCluster,
  buildDust,
  buildSky,
  personHues,
} from "./sky";

// One string per person, which is all a sky was ever hashed from. These are
// the old name + handle pairs run together, so every assertion below sweeps
// exactly the seed space it swept before the callers stopped concatenating.
const ROS = "Rosalind Franklin@ros_franklin";
const ALAN = "Alan Kayalan-kay";

describe("personHues", () => {
  test("derives three stable hues from identity", () => {
    const a = personHues(ROS);
    const b = personHues(ROS);
    expect(a).toEqual(b);
    expect(a).toHaveLength(3);
    a.forEach((h) => {
      expect(h).toBeGreaterThanOrEqual(0);
      expect(h).toBeLessThan(360);
    });
  });

  test("different people get different hues", () => {
    expect(personHues(ROS)).not.toEqual(
      personHues(ALAN),
    );
  });
});

describe("buildSky", () => {
  test("is fully deterministic for the same person", () => {
    const a = buildSky(ROS);
    const b = buildSky(ROS);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  test("different people mint different skies", () => {
    const a = buildSky(ROS);
    const b = buildSky(ALAN);
    expect(JSON.stringify(a)).not.toBe(JSON.stringify(b));
  });

  test("constellation stars keep their distance and stay in bounds", () => {
    const sky = buildSky(ROS);
    expect(sky.majors.length).toBeGreaterThanOrEqual(7);
    expect(sky.majors.length).toBeLessThanOrEqual(9);
    for (const star of sky.majors) {
      expect(star.x).toBeGreaterThanOrEqual(sky.pad);
      expect(star.x).toBeLessThanOrEqual(sky.width - sky.pad);
      expect(star.y).toBeGreaterThanOrEqual(sky.pad);
      expect(star.y).toBeLessThanOrEqual(sky.height * 0.62);
    }
    for (let i = 0; i < sky.majors.length; i++) {
      for (let j = i + 1; j < sky.majors.length; j++) {
        const dx = sky.majors[i].x - sky.majors[j].x;
        const dy = sky.majors[i].y - sky.majors[j].y;
        expect(Math.hypot(dx, dy)).toBeGreaterThanOrEqual(68);
      }
    }
  });

  test("the figure is a spanning tree: exactly n-1 calm edges", () => {
    const sky = buildSky(ROS);
    expect(sky.edges).toHaveLength(sky.majors.length - 1);
    for (const [a, b] of sky.edges) {
      expect(a).toBeGreaterThanOrEqual(0);
      expect(b).toBeGreaterThanOrEqual(0);
      expect(a).toBeLessThan(sky.majors.length);
      expect(b).toBeLessThan(sky.majors.length);
    }
  });

  test("deep field density: many faint minors on a power law", () => {
    const sky = buildSky(ROS);
    expect(sky.minors).toHaveLength(150);
    for (const star of sky.minors) {
      expect(star.r).toBeGreaterThanOrEqual(0.4);
      expect(star.r).toBeLessThanOrEqual(1.8);
      expect(star.dur).toBeGreaterThan(0);
      expect(star.rvd).toBeGreaterThanOrEqual(0);
      expect(star.rvd).toBeLessThan(1);
    }
    // Power law: small stars must far outnumber large ones.
    const small = sky.minors.filter((s) => s.r < 0.8).length;
    expect(small).toBeGreaterThan(sky.minors.length / 2);
  });

  test("nebulae and giants carry the person's hues", () => {
    const sky = buildSky(ROS);
    const hues = personHues(ROS);
    expect(sky.nebulae).toHaveLength(3);
    for (const nebula of sky.nebulae) {
      expect(hues).toContain(nebula.hue);
    }
    expect(sky.giants.length).toBeGreaterThan(0);
    for (const giant of sky.giants) {
      expect(hues).toContain(giant.hue);
    }
  });

  test("the two brightest constellation stars get flares", () => {
    const sky = buildSky(ROS);
    expect(sky.flares).toHaveLength(2);
    const majorPositions = sky.majors.map((m) => `${m.x},${m.y}`);
    for (const flare of sky.flares) {
      expect(majorPositions).toContain(`${flare.x},${flare.y}`);
    }
  });

  test("flags a bounded handful of featured minors for individual twinkle", () => {
    for (const p of [ROS, ALAN]) {
      const featured = buildSky(p).minors.filter((s) => s.featured);
      // ~20-24 alive minors; the rest render static under group shimmer.
      expect(featured.length).toBeGreaterThanOrEqual(20);
      expect(featured.length).toBeLessThanOrEqual(24);
    }
  });

  test("the featured set is stable for a given person", () => {
    const a = buildSky(ROS).minors.map((s) => !!s.featured);
    const b = buildSky(ROS).minors.map((s) => !!s.featured);
    expect(a).toEqual(b);
  });

  test("featured is a minors-only concept: majors and giants stay alive", () => {
    const sky = buildSky(ROS);
    for (const m of sky.majors) expect(m.featured).toBeUndefined();
    for (const g of sky.giants) expect(g.featured).toBeUndefined();
  });
});

describe("the seed is one string, hashed the way it always was", () => {
  // A sky is a promise: same person, same figure, forever. These numbers were
  // dumped from the two-argument buildSky(name, handle) that shipped before
  // the seed was unified, so they are the proof that handing the same
  // characters over as one string moved nobody's stars.

  test("the old name + handle pair, run together, mints the old sky", () => {
    const sky = buildSky("Rosalind Franklin@ros_franklin");
    expect(sky.hues).toEqual([344, 121, 318]);
    expect(sky.majors).toHaveLength(7);
    expect(sky.majors[0].x).toBe(336.21452886238694);
    expect(sky.majors[0].y).toBe(293.0253099120222);
    expect(sky.majors[0].r).toBe(3.386791331227869);
    expect(sky.majors[0].hue).toBe(344);
    expect(sky.edges).toEqual([
      [0, 4],
      [4, 6],
      [4, 1],
      [1, 5],
      [5, 3],
      [6, 2],
    ]);
    expect(sky.minors[0].x).toBe(250.89263597130775);
    expect(sky.minors[0].y).toBe(354.6653774008155);
    expect(sky.shoot.x1).toBe(194.2717980965972);
    expect(sky.shoot.delay).toBe(10.069262959063053);
  });

  test("a lone seed, which used to mean a name with no handle, is unchanged", () => {
    expect(personHues("ada")).toEqual([163, 190, 358]);
    const sky = buildSky("ada");
    expect(sky.majors).toHaveLength(8);
    expect(sky.majors[0].x).toBe(41.70665299706161);
    expect(sky.majors[0].y).toBe(250.63980596438049);
    expect(sky.majors[0].r).toBe(2.692375229205936);
    expect(sky.edges).toEqual([
      [0, 2],
      [2, 6],
      [6, 3],
      [3, 1],
      [3, 4],
      [1, 5],
      [0, 7],
    ]);
  });
});

describe("buildSky invariants across many identities", () => {
  // The constellation figure comes from rejection sampling (retry until the
  // minimum-separation constraint is met), so a single fixed test person
  // cannot catch a seed where that loop misbehaves. Sweep a wide,
  // deterministic set of identities instead.
  const NAMES = Array.from({ length: 100 }, (_, i) => `name-${i}`);

  test("bounds, edge count, and separation hold for every generated identity", () => {
    for (const name of NAMES) {
      const sky = buildSky(`${name}@${name}`);

      for (const star of sky.majors) {
        expect(star.x).toBeGreaterThanOrEqual(sky.pad);
        expect(star.x).toBeLessThanOrEqual(sky.width - sky.pad);
        expect(star.y).toBeGreaterThanOrEqual(sky.pad);
        expect(star.y).toBeLessThanOrEqual(sky.height * 0.62);
      }
      for (let i = 0; i < sky.majors.length; i++) {
        for (let j = i + 1; j < sky.majors.length; j++) {
          const dx = sky.majors[i].x - sky.majors[j].x;
          const dy = sky.majors[i].y - sky.majors[j].y;
          expect(Math.hypot(dx, dy)).toBeGreaterThanOrEqual(68);
        }
      }
      expect(sky.edges).toHaveLength(sky.majors.length - 1);
      for (const [a, b] of sky.edges) {
        expect(a).toBeGreaterThanOrEqual(0);
        expect(b).toBeGreaterThanOrEqual(0);
        expect(a).toBeLessThan(sky.majors.length);
        expect(b).toBeLessThan(sky.majors.length);
      }
    }
  });
});

describe("buildCluster", () => {
  test("is deterministic for the same person", () => {
    const a = buildCluster(ROS);
    const b = buildCluster(ROS);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  test("mirrors buildSky's constellation topology exactly", () => {
    // The map cluster must be recognizably the same figure as the card sky:
    // same star count, same minimum-spanning-tree edges.
    const sky = buildSky(ROS);
    const cluster = buildCluster(ROS);
    expect(cluster.stars).toHaveLength(sky.majors.length);
    expect(cluster.edges).toEqual(sky.edges);
  });

  test("its stars are that same seed's majors, in order, only rescaled", () => {
    // "Recognizably the same figure" has to mean more than a matching star
    // count: each cluster star is one major, in the same slot, carrying the
    // same hue, and the rescale is affine so the figure cannot be reflected
    // or reshuffled on the way to the map.
    const sky = buildSky(ROS);
    const cluster = buildCluster(ROS);
    expect(cluster.stars.map((s) => s.hue)).toEqual(sky.majors.map((m) => m.hue));
    const rank = <T,>(items: T[], of: (item: T) => number) =>
      items
        .map((item, i) => ({ i, v: of(item) }))
        .sort((a, b) => a.v - b.v)
        .map((entry) => entry.i);
    expect(rank(cluster.stars, (s) => s.x)).toEqual(rank(sky.majors, (m) => m.x));
    expect(rank(cluster.stars, (s) => s.y)).toEqual(rank(sky.majors, (m) => m.y));
  });

  test("scales every star inside the padded cluster box", () => {
    const width = 120;
    const height = 92;
    const pad = 8;
    const cluster = buildCluster(ROS, { width, height, pad });
    expect(cluster.width).toBe(width);
    expect(cluster.height).toBe(height);
    for (const star of cluster.stars) {
      expect(star.x).toBeGreaterThanOrEqual(pad);
      expect(star.x).toBeLessThanOrEqual(width - pad);
      expect(star.y).toBeGreaterThanOrEqual(pad);
      expect(star.y).toBeLessThanOrEqual(height - pad);
      expect(star.r).toBeGreaterThan(0);
    }
  });

  test("honors custom box dimensions", () => {
    const cluster = buildCluster(ALAN, {
      width: 96,
      height: 72,
      pad: 6,
    });
    for (const star of cluster.stars) {
      expect(star.x).toBeGreaterThanOrEqual(6);
      expect(star.x).toBeLessThanOrEqual(90);
      expect(star.y).toBeGreaterThanOrEqual(6);
      expect(star.y).toBeLessThanOrEqual(66);
    }
  });

  test("different people mint different clusters", () => {
    expect(JSON.stringify(buildCluster(ROS))).not.toBe(
      JSON.stringify(buildCluster(ALAN)),
    );
  });
});

describe("atlasLayout", () => {
  const W = 1200;
  const H = 800;

  test("is deterministic and returns one point per person", () => {
    const a = atlasLayout(12, W, H);
    const b = atlasLayout(12, W, H);
    expect(a).toEqual(b);
    expect(a).toHaveLength(12);
  });

  test("keeps every cluster box and label inside the viewport", () => {
    const boxW = 120;
    const boxH = 92;
    const labelH = 46;
    const points = atlasLayout(20, W, H, { boxW, boxH, labelH });
    for (const p of points) {
      expect(p.x - boxW / 2).toBeGreaterThanOrEqual(0);
      expect(p.x + boxW / 2).toBeLessThanOrEqual(W);
      expect(p.y - boxH / 2).toBeGreaterThanOrEqual(0);
      expect(p.y + boxH / 2 + labelH).toBeLessThanOrEqual(H);
    }
  });

  test("fits a narrow mobile viewport with a smaller box", () => {
    const boxW = 96;
    const boxH = 72;
    const labelH = 40;
    const points = atlasLayout(20, 390, 780, { boxW, boxH, labelH });
    for (const p of points) {
      expect(p.x - boxW / 2).toBeGreaterThanOrEqual(0);
      expect(p.x + boxW / 2).toBeLessThanOrEqual(390);
      expect(p.y - boxH / 2).toBeGreaterThanOrEqual(0);
      expect(p.y + boxH / 2 + labelH).toBeLessThanOrEqual(780);
    }
  });

  test("orders clusters center-out by recency: newest nearest the center", () => {
    const count = 12;
    const points = atlasLayout(count, W, H);
    const cx = W / 2;
    const cy = H / 2 + 14; // matches the default center offset
    const dist = (p: { x: number; y: number }) =>
      Math.hypot(p.x - cx, p.y - cy);
    const distances = points.map(dist);
    // Index 0 (newest) is strictly the closest star to the center.
    for (let i = 1; i < count; i++) {
      expect(distances[0]).toBeLessThan(distances[i]);
    }
    expect(distances[0]).toBeLessThan(distances[count - 1]);
  });

  test("never returns NaN, even for a single person or an empty sky", () => {
    expect(atlasLayout(0, W, H)).toEqual([]);
    const one = atlasLayout(1, W, H);
    expect(one).toHaveLength(1);
    expect(Number.isFinite(one[0].x)).toBe(true);
    expect(Number.isFinite(one[0].y)).toBe(true);
  });
});

describe("buildDust", () => {
  test("is deterministic and shared, not per person", () => {
    expect(buildDust()).toEqual(buildDust());
  });

  test("defaults to a full field of unit-coordinate faint stars", () => {
    const dust = buildDust();
    expect(dust).toHaveLength(80);
    for (const star of dust) {
      expect(star.x).toBeGreaterThanOrEqual(0);
      expect(star.x).toBeLessThan(1);
      expect(star.y).toBeGreaterThanOrEqual(0);
      expect(star.y).toBeLessThan(1);
      expect(star.r).toBeGreaterThan(0);
      // Dust stays faint so it never competes with a person's constellation.
      expect(star.hi).toBeLessThan(0.4);
      expect(star.dur).toBeGreaterThan(0);
    }
  });

  test("honors a custom count", () => {
    expect(buildDust(40)).toHaveLength(40);
  });
});
