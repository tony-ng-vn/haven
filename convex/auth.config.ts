import { AuthConfig } from "convex/server";

export default {
  providers: [
    {
      // Clerk's Frontend API URL. Set CLERK_JWT_ISSUER_DOMAIN on the Convex
      // deployment (dashboard or `npx convex env set`) -- see the "convex"
      // JWT template in the Clerk dashboard for the exact issuer value.
      domain: process.env.CLERK_JWT_ISSUER_DOMAIN!,
      // Must match the JWT template name in Clerk (the template's `aud`
      // claim is checked against this value).
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
