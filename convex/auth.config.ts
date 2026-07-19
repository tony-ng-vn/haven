import { AuthConfig } from "convex/server";

// Clerk's Frontend API URL. Set CLERK_JWT_ISSUER_DOMAIN on the Convex
// deployment (dashboard or `npx convex env set`) -- see the "convex" JWT
// template in the Clerk dashboard for the exact issuer value. A missing
// value used to resolve silently to `domain: undefined`, which only ever
// surfaced as an opaque "not authenticated" failure at sign-in time.
function issuerDomain(): string {
  const domain = process.env.CLERK_JWT_ISSUER_DOMAIN;
  if (domain === undefined || domain === "") {
    throw new Error(
      "CLERK_JWT_ISSUER_DOMAIN is not set on the Convex deployment. Run: npx convex env set CLERK_JWT_ISSUER_DOMAIN <domain>",
    );
  }
  return domain;
}

export default {
  providers: [
    {
      domain: issuerDomain(),
      // Must match the JWT template name in Clerk (the template's `aud`
      // claim is checked against this value).
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
