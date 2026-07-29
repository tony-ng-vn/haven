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

describe("the content security policy", () => {
  test("is served on every path", () => {
    expect(csp).toBeDefined();
    const all = vercel.headers.find((entry) => entry.source === "/(.*)");
    expect(all?.headers.some((h) => h.key.startsWith("Content-Security-Policy"))).toBe(
      true,
    );
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

  // Convex is reached over both https and a websocket; allowing only the first
  // gives a page that loads and then never updates.
  test("allows Convex over https and websocket", () => {
    expect(directive("connect-src")).toContain(CONVEX_PRODUCTION);
    expect(directive("connect-src")).toContain("wss://third-hound-186.convex.cloud");
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

  // Deliberately Report-Only, and this test is where that decision is written
  // down rather than inferred from a header nobody reads. Flipping it to the
  // enforcing name is a one-word change; it has not been made because no one
  // has yet loaded the site and confirmed the console is clean, and getting it
  // wrong breaks sign-in in production. Update this test in the same commit
  // that flips it.
  test("is Report-Only until somebody has watched it report nothing", () => {
    expect(csp?.key).toBe("Content-Security-Policy-Report-Only");
  });
});
