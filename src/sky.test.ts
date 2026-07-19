import { describe, expect, test } from "vitest";
import {
  atlasLayout,
  buildCluster,
  buildDust,
  buildSky,
  personHues,
} from "./sky";

const ROS = { name: "Rosalind Franklin", handle: "@ros_franklin" };
const ALAN = { name: "Alan Kay", handle: "alan-kay" };

describe("personHues", () => {
  test("derives three stable hues from identity", () => {
    const a = personHues(ROS.name, ROS.handle);
    const b = personHues(ROS.name, ROS.handle);
    expect(a).toEqual(b);
    expect(a).toHaveLength(3);
    a.forEach((h) => {
      expect(h).toBeGreaterThanOrEqual(0);
      expect(h).toBeLessThan(360);
    });
  });

  test("different people get different hues", () => {
    expect(personHues(ROS.name, ROS.handle)).not.toEqual(
      personHues(ALAN.name, ALAN.handle),
    );
  });
});

describe("buildSky", () => {
  test("is fully deterministic for the same person", () => {
    const a = buildSky(ROS.name, ROS.handle);
    const b = buildSky(ROS.name, ROS.handle);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  test("different people mint different skies", () => {
    const a = buildSky(ROS.name, ROS.handle);
    const b = buildSky(ALAN.name, ALAN.handle);
    expect(JSON.stringify(a)).not.toBe(JSON.stringify(b));
  });

  test("constellation stars keep their distance and stay in bounds", () => {
    const sky = buildSky(ROS.name, ROS.handle);
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
    const sky = buildSky(ROS.name, ROS.handle);
    expect(sky.edges).toHaveLength(sky.majors.length - 1);
    for (const [a, b] of sky.edges) {
      expect(a).toBeGreaterThanOrEqual(0);
      expect(b).toBeGreaterThanOrEqual(0);
      expect(a).toBeLessThan(sky.majors.length);
      expect(b).toBeLessThan(sky.majors.length);
    }
  });

  test("deep field density: many faint minors on a power law", () => {
    const sky = buildSky(ROS.name, ROS.handle);
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
    const sky = buildSky(ROS.name, ROS.handle);
    const hues = personHues(ROS.name, ROS.handle);
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
    const sky = buildSky(ROS.name, ROS.handle);
    expect(sky.flares).toHaveLength(2);
    const majorPositions = sky.majors.map((m) => `${m.x},${m.y}`);
    for (const flare of sky.flares) {
      expect(majorPositions).toContain(`${flare.x},${flare.y}`);
    }
  });

  test("flags a bounded handful of featured minors for individual twinkle", () => {
    for (const p of [ROS, ALAN]) {
      const featured = buildSky(p.name, p.handle).minors.filter(
        (s) => s.featured,
      );
      // ~20-24 alive minors; the rest render static under group shimmer.
      expect(featured.length).toBeGreaterThanOrEqual(20);
      expect(featured.length).toBeLessThanOrEqual(24);
    }
  });

  test("the featured set is stable for a given person", () => {
    const a = buildSky(ROS.name, ROS.handle).minors.map((s) => !!s.featured);
    const b = buildSky(ROS.name, ROS.handle).minors.map((s) => !!s.featured);
    expect(a).toEqual(b);
  });

  test("featured is a minors-only concept: majors and giants stay alive", () => {
    const sky = buildSky(ROS.name, ROS.handle);
    for (const m of sky.majors) expect(m.featured).toBeUndefined();
    for (const g of sky.giants) expect(g.featured).toBeUndefined();
  });
});

describe("buildCluster", () => {
  test("is deterministic for the same person", () => {
    const a = buildCluster(ROS.name, ROS.handle);
    const b = buildCluster(ROS.name, ROS.handle);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });

  test("mirrors buildSky's constellation topology exactly", () => {
    // The map cluster must be recognizably the same figure as the card sky:
    // same star count, same minimum-spanning-tree edges.
    const sky = buildSky(ROS.name, ROS.handle);
    const cluster = buildCluster(ROS.name, ROS.handle);
    expect(cluster.stars).toHaveLength(sky.majors.length);
    expect(cluster.edges).toEqual(sky.edges);
  });

  test("scales every star inside the padded cluster box", () => {
    const width = 120;
    const height = 92;
    const pad = 8;
    const cluster = buildCluster(ROS.name, ROS.handle, { width, height, pad });
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
    const cluster = buildCluster(ALAN.name, ALAN.handle, {
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
    expect(JSON.stringify(buildCluster(ROS.name, ROS.handle))).not.toBe(
      JSON.stringify(buildCluster(ALAN.name, ALAN.handle)),
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
