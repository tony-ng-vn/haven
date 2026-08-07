import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

// The Content-Security-Policy in vercel.json is a list of hosts that has to
// agree with three other places nothing connects it to: the Clerk instance in
// Config.swift and on Vercel, the Convex deployments in Config.swift and
// .env.local, and whatever Clerk's own UI loads at runtime. Nothing imports
// this file, so nothing catches a host that was never added -- which is exactly
// how img.clerk.com came to be missing while the sign-in UI loaded avatars and
// provider logos from it.
//
// A missing host does not fail loudly either. Under Report-Only it is a console
// message nobody is watching; enforced, it is a broken image or a sign-in that
// silently does nothing. So the policy is asserted here instead.

const vercel = JSON.parse(readFileSync("vercel.json", "utf8")) as {
  headers: { source: string; headers: { key: string; value: string }[] }[];
};

const csp = vercel.headers
  .flatMap((entry) => entry.headers)
  .find((header) => header.key.startsWith("Content-Security-Policy"));

/// The hosts allowed for one directive.
function directive(name: string): string[] {
  const found = (csp?.value ?? "")
    .split(";")
    .map((part) => part.trim())
    .find((part) => part === name || part.startsWith(`${name} `));
  if (found === undefined) return [];
  return found.split(/\s+/).slice(1);
}

const CLERK_PRODUCTION = "https://clerk.inhavens.com";
const CLERK_DEVELOPMENT = "https://valued-bonefish-64.clerk.accounts.dev";
const CONVEX_PRODUCTION = "https://third-hound-186.convex.cloud";
// VITE_FEEDBACK_ENDPOINT, compiled into the bundle at build time.
const FEEDBACK_SERVICE = "https://glorious-gerbil-332.convex.site";

// The general rule's source is no longer the bare "/(.*)"  -- it carries a
// negative lookahead excluding "/demo-sky.html", which gets its own narrower
// policy below. A change to that regex string is exactly the kind of edit
// that must never be pinned by string equality: read wrong, it could exclude
// far more than one path and silently drop the policy everywhere else. This
// builds a real RegExp from the committed source and checks it behaves,
// rather than checking that the string matches itself. It approximates
// Vercel's own path matcher (full-path anchored regex) rather than being it.
function matchesGeneralSource(pathname: string): boolean {
  const generalSource = vercel.headers.find(
    (entry) => entry.headers.some((h) => h.key === "X-Frame-Options"),
  )?.source;
  expect(generalSource, "no general security-header rule found").toBeDefined();
  const pattern = new RegExp(`^${generalSource}$`);
  return pattern.test(pathname);
}

describe("the content security policy", () => {
  test("is served on every ordinary path", () => {
    expect(csp).toBeDefined();
    for (const path of [
      "/",
      "/privacy",
      "/terms",
      "/support",
      "/mayachen",
      "/api/sky-download",
      "/assets/index-abc.js",
    ]) {
      expect(matchesGeneralSource(path), `${path} should carry the general policy`).toBe(
        true,
      );
    }
  });

  // demo-sky.html is a self-contained, given file (see its own describe block
  // below) that needs a narrower, more permissive policy to run at all. It
  // must be carved out of the general rule, not merely have a second rule
  // added alongside it -- Vercel merges headers from every matching rule, so
  // an additional permissive CSP does nothing while the strict one is still
  // also sent (multiple CSP headers enforce their intersection).
  test("does not carry the general policy -- it has its own, asserted below", () => {
    expect(matchesGeneralSource("/demo-sky.html")).toBe(false);
  });

  // Clerk documents these four. Miss one and sign-in fails in a way that points
  // at nothing: script-src kills it outright, connect-src hangs it, frame-src
  // breaks bot protection, and img-src leaves the provider buttons blank.
  test("allows everything Clerk's sign-in UI needs", () => {
    expect(directive("script-src")).toContain(CLERK_PRODUCTION);
    expect(directive("connect-src")).toContain(CLERK_PRODUCTION);
    expect(directive("frame-src")).toContain(CLERK_PRODUCTION);
    // Avatars and provider logos are served from Clerk's image host, which is
    // not the instance domain and so is easy to forget.
    expect(directive("img-src")).toContain("https://img.clerk.com");
    // Clerk's bot protection is a Cloudflare challenge in an iframe.
    expect(directive("frame-src")).toContain("https://challenges.cloudflare.com");
  });

  // Both instances are named on purpose while previews still sign in against
  // development. When that stops being true, these lines are the reminder that
  // the development entries can go.
  test("names both Clerk instances while previews still need the dev one", () => {
    for (const name of ["script-src", "connect-src", "frame-src"]) {
      expect(directive(name)).toContain(CLERK_DEVELOPMENT);
    }
  });

  // The landing hero embeds its own sample sky in an iframe -- a same-origin
  // frame the site was never asked to open before. frame-src governs what
  // this site may embed, not who may embed this site, so widening it here
  // does not loosen the site's own clickjacking protection (X-Frame-Options
  // above stays DENY on every path except the isolated one below).
  test("allows the landing page to embed its own same-origin demo", () => {
    expect(directive("frame-src")).toContain("'self'");
  });

  // Convex is reached over both https and a websocket; allowing only the first
  // gives a page that loads and then never updates.
  test("allows Convex over https and websocket", () => {
    expect(directive("connect-src")).toContain(CONVEX_PRODUCTION);
    expect(directive("connect-src")).toContain("wss://third-hound-186.convex.cloud");
  });

  // The feedback widget posts to its own hosted service, a different Convex
  // deployment from ours. It is admin-only, so under Report-Only a missing
  // entry here broke nothing anyone would notice and nothing anyone would see
  // -- the exact shape of bug that makes enforcing worth doing.
  test("allows the feedback widget to reach its own service", () => {
    expect(directive("connect-src")).toContain(FEEDBACK_SERVICE);
  });

  // Card photos and capture screenshots are Convex storage urls.
  test("allows the images the product actually renders", () => {
    expect(directive("img-src")).toContain(CONVEX_PRODUCTION);
    expect(directive("img-src")).toContain("data:");
    expect(directive("img-src")).toContain("blob:");
  });

  test("keeps the defaults that make the rest of the policy mean anything", () => {
    expect(directive("default-src")).toEqual(["'self'"]);
    expect(directive("base-uri")).toEqual(["'self'"]);
    expect(directive("form-action")).toEqual(["'self'"]);
  });

  // Enforced as of 2026-07-29. Report-Only protected nothing: a missing host
  // was a console message nobody was watching, which is how img.clerk.com and
  // the feedback endpoint below both went missing while the policy looked
  // maintained. Flipping it back is a one-word change if something turns out
  // to be missing, and this test is where that decision lives.
  test("is enforced, not merely reported", () => {
    expect(csp?.key).toBe("Content-Security-Policy");
  });
});

// demo-sky.html is a given file, not generated here: a single self-contained
// page with its own inline <script> and <style> and no external requests at
// all. It is no longer linked from anywhere in this app -- its one consumer,
// the landing hero component that embedded it, was deleted once the owner
// picked Landing2Page.tsx as the front door instead (see resolveView in
// lib.ts) -- but the file and this CSP carve-out stay: deleting deploy config
// like the vercel.json rule below is a separate call the lead makes, not one
// this cleanup pass makes on its own. The site's general policy blocks
// inline script execution and framing outright, so this file needs its own
// narrower rule rather than an exception carved into the policy every other
// page relies on.
describe("the demo-sky.html policy", () => {
  const entry = vercel.headers.find((h) => h.source === "/demo-sky.html");

  function demoDirective(name: string): string[] {
    const value =
      entry?.headers.find((h) => h.key === "Content-Security-Policy")?.value ??
      "";
    const found = value
      .split(";")
      .map((part) => part.trim())
      .find((part) => part === name || part.startsWith(`${name} `));
    return found === undefined ? [] : found.split(/\s+/).slice(1);
  }

  test("exists as its own rule", () => {
    expect(entry, "no dedicated rule for /demo-sky.html").toBeDefined();
  });

  // Without this the inline script and style that build the whole demo
  // simply do not run -- same-origin framing is not the only thing that was
  // blocked. A hash instead of 'unsafe-inline' is deliberately not used: the
  // file is regenerated wholesale (like the download zip), and a hash would
  // silently break on the next refresh rather than failing a test.
  test("permits the inline script and style the file is built from", () => {
    expect(demoDirective("script-src")).toContain("'unsafe-inline'");
    expect(demoDirective("style-src")).toContain("'unsafe-inline'");
  });

  test("permits being framed by this site, and only this site", () => {
    const frameOptions = entry?.headers.find(
      (h) => h.key === "X-Frame-Options",
    )?.value;
    expect(frameOptions).toBe("SAMEORIGIN");
    expect(demoDirective("frame-ancestors")).toEqual(["'self'"]);
  });

  test("makes no outbound requests, so nothing else needs opening", () => {
    expect(demoDirective("connect-src")).toEqual(["'self'"]);
    expect(demoDirective("img-src")).toEqual(["'self'", "data:"]);
  });
});
