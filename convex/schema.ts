import { defineSchema } from "convex/server";
import { authTables } from "@convex-dev/auth/server";

// The people table is added in Task 2.
export default defineSchema({
  ...authTables,
});
