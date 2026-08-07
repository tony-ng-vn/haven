import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

import {
  CLERK_ROUTING,
  CLERK_SIGN_IN_URL,
  CLERK_SIGN_UP_URL,
  clerkUrlProps,
} from "./clerkConfig";
import { isAuthPath, resolveView } from "./lib";
import { isClaimableHandle } from "../convex/handleNames";

// The offline half of the guard against the production sign-in loop.
//
// Neither of these settings does anything visible on a development Clerk
// instance, which is the whole reason the loop shipped: it was invisible in
// every environment anybody could run until the production key landed. So the
// values are asserted here rather than trusted to survive a refactor, and the
// live instance is checked separately by .github/workflows/clerk-config.yml,
// which is the half that can see the dashboard.

describe("the Clerk urls Haven declares", () => {
  // Without these, Clerk falls back to whatever the instance advertises --
  // which on a production instance is the Account Portal at accounts.<domain>,
  // and that redirects straight back here.
  test("the provider is told where sign-in and sign-up live", () => {
    expect(clerkUrlProps.signInUrl).toBe(CLERK_SIGN_IN_URL);
    expect(clerkUrlProps.signUpUrl).toBe(CLERK_SIGN_UP_URL);
  });

  test("they are Haven's own routes, never an Account Portal", () => {
    for (const url of [CLERK_SIGN_IN_URL, CLERK_SIGN_UP_URL]) {
      expect(url.startsWith("/")).toBe(true);
      expect(url).not.toMatch(/accounts\./);
    }
  });

  // A url Clerk redirects to that the router drops on the waitlist is the same
  // dead end by a different route. Auth now lives inside the preview portal.
  test("the router actually answers both of them", () => {
    const base = {
      isAuthenticated: false,
      isLoading: false,
      hash: "",
      hasSessionHint: false,
    };
    for (const url of [CLERK_SIGN_IN_URL, CLERK_SIGN_UP_URL]) {
      expect(isAuthPath(url)).toBe(true);
      expect(resolveView({ ...base, pathname: url })).toBe("preview");
    }
  });

  // If either word became claimable, somebody could hold the card that Clerk
  // sends people to in order to sign in.
  test("nobody can claim the sign-in routes as a handle", () => {
    expect(isClaimableHandle("signin")).toBe(false);
    expect(isClaimableHandle("signup")).toBe(false);
    expect(isClaimableHandle("login")).toBe(false);
  });

  // "path" would have the component navigate, which is what reached the portal
  // in the first place. "hash" keeps every step in the fragment.
  test("the prebuilt component routes in the hash, not by navigating", () => {
    expect(CLERK_ROUTING).toBe("hash");
  });

  test("the component is mounted with that routing, not the default", () => {
    const portal = readFileSync("src/PreviewPortal.tsx", "utf8");
    expect(portal).toMatch(/<ClerkSignIn[^>]*routing=\{CLERK_ROUTING\}/);
  });

  test("the provider is given the urls, not just handed them", () => {
    const main = readFileSync("src/main.tsx", "utf8");
    expect(main).toContain("{...clerkUrlProps}");
  });
});
