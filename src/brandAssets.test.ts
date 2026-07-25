import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

describe("Haven brand assets", () => {
  test("site icons and OG card use Nori PNGs", () => {
    const html = readFileSync(join(root, "index.html"), "utf8");
    expect(html).toContain('rel="icon" href="/favicon.ico"');
    expect(html).toContain('href="/favicon-32x32.png"');
    expect(html).toContain('href="/apple-touch-icon.png"');
    expect(html).toContain("https://inhavens.com/og.png");
    expect(html).toMatch(/<title>Haven[^<]*<\/title>/);
    expect(html).not.toMatch(/euno/i);
    expect(html).not.toContain("icon.svg");

    const manifest = JSON.parse(
      readFileSync(join(root, "public/manifest.webmanifest"), "utf8"),
    );
    expect(manifest.name).toBe("Haven");
    expect(manifest.short_name).toBe("Haven");
    expect(manifest.icons.map((icon: { src: string }) => icon.src)).toEqual([
      "/icon-192.png",
      "/icon-512.png",
      "/icon-maskable-512.png",
    ]);

    for (const file of [
      "favicon.ico",
      "favicon-16x16.png",
      "favicon-32x32.png",
      "apple-touch-icon.png",
      "icon-192.png",
      "icon-512.png",
      "icon-maskable-512.png",
      "og.png",
    ]) {
      expect(existsSync(join(root, "public", file))).toBe(true);
    }
    expect(existsSync(join(root, "brand/nori.png"))).toBe(true);
  });

  test("package name is haven-app", () => {
    const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
    expect(pkg.name).toBe("haven-app");
  });
});
