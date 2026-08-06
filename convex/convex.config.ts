import { defineApp } from "convex/server";
import rateLimiter from "@convex-dev/rate-limiter/convex.config.js";

// The first component this app mounts (identity brief, X3): per-key quotas
// belong to @convex-dev/rate-limiter rather than a hand-rolled window scan
// (guidelines.md's component section), starting with the two X-lookup caps
// composio.ts introduced. convex/rateLimit.ts's older, unshaded
// checkRateLimit predates this and stays for now -- see its own comment.
const app = defineApp();
app.use(rateLimiter);
export default app;
