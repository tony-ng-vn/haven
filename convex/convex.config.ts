import { defineApp } from "convex/server";
import { v } from "convex/values";
import rateLimiter from "@convex-dev/rate-limiter/convex.config.js";

// The first component this app mounts (identity brief, X3): per-key quotas
// belong to @convex-dev/rate-limiter rather than a hand-rolled window scan
// (guidelines.md's component section), starting with the two X-lookup caps
// composio.ts introduced. convex/rateLimit.ts's older, unshaded
// checkRateLimit predates this and stays for now -- see its own comment.
const app = defineApp({
  env: {
    // The shared early-preview code lives on the deployment, never in the
    // browser bundle. Access granted with it is persisted per Clerk account.
    HAVEN_PREVIEW_CODE: v.string(),
  },
});
app.use(rateLimiter);
export default app;
