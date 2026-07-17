import { describe, expect, test } from "vitest";
import { buildSky, personHues } from "./sky";

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
});
