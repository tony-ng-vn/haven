import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, test } from "vitest";

// Search engines rank us for the brand query "inhavens" only if that token
// actually appears where they look: title, structured data, and visible copy.
// The domain alone is not enough (it ranked us 5th behind inhaven.com).
// These tests lock the brand token in place so a copy pass cannot silently
// drop it and sink the ranking again.

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const indexHtml = readFileSync(join(root, "index.html"), "utf8");

describe("brand SEO for the inhavens query", () => {
  test("title carries both brand names and survives SERP truncation", () => {
    const title = indexHtml.match(/<title>([^<]*)<\/title>/)?.[1] ?? "";
    // Both names must be in the title itself. Google's site-name feature is
    // supposed to surface "Haven" from the JSON-LD on its own line, but it
    // frequently falls back to the bare domain -- so the title cannot be the
    // only place either name lives.
    expect(title).toContain("Haven");
    expect(title.toLowerCase()).toContain("inhavens");
    // Google truncates titles around 60 characters and is likelier to discard
    // an over-long title and write its own. Both brand tokens sit in the first
    // 20 characters, so a trim never costs us the ranking signal.
    expect(title.length).toBeLessThanOrEqual(60);
  });

  test("meta description mentions inhavens.com", () => {
    const description =
      indexHtml.match(/<meta name="description" content="([^"]*)"/)?.[1] ?? "";
    expect(description.toLowerCase()).toContain("inhavens.com");
  });

  test("canonical URL is declared", () => {
    expect(indexHtml).toContain(
      '<link rel="canonical" href="https://inhavens.com/" />',
    );
  });

  test("structured data names the site with Inhavens as an alternate name", () => {
    const jsonLd = indexHtml.match(
      /<script type="application\/ld\+json">([\s\S]*?)<\/script>/,
    )?.[1];
    expect(jsonLd).toBeDefined();
    const graph = JSON.parse(jsonLd ?? "")["@graph"] as Array<
      Record<string, unknown>
    >;
    const types = graph.map((node) => node["@type"]);
    expect(types).toContain("WebSite");
    expect(types).toContain("Organization");
    for (const node of graph) {
      expect(node.name).toBe("Haven");
      expect(node.alternateName).toContain("Inhavens");
      expect(node.url).toBe("https://inhavens.com/");
    }
  });

  test("favicon is a crawlable file, not a data URI", () => {
    // Google's favicon crawler cannot index data: URIs; the SERP fell back to
    // a generic letter tile. The icon must live at a real URL.
    expect(indexHtml).not.toMatch(/rel="icon"[^>]*href="data:/);
    expect(indexHtml).toMatch(/<link rel="icon"[^>]*href="\/favicon\.ico"/);
  });

  test("robots.txt allows crawling and points at the sitemap", () => {
    const robots = readFileSync(join(root, "public", "robots.txt"), "utf8");
    expect(robots).toContain("User-agent: *");
    expect(robots).not.toMatch(/^Disallow: \/$/m);
    expect(robots).toContain("Sitemap: https://inhavens.com/sitemap.xml");
  });

  test("sitemap lists the landing page", () => {
    const sitemap = readFileSync(join(root, "public", "sitemap.xml"), "utf8");
    expect(sitemap).toContain("<loc>https://inhavens.com/</loc>");
  });

  test("the waitlist form renders the domain as visible text", () => {
    // The layout owns this mention (SEO chrome), not the copy deck; see the
    // comment beside the fine print in WaitlistForm.tsx.
    const waitlistForm = readFileSync(
      join(root, "src", "WaitlistForm.tsx"),
      "utf8",
    );
    expect(waitlistForm).toContain("inhavens.com");
  });
});
