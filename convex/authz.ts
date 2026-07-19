// Plain helper, not a registered Convex function -- importing it from
// people.ts and captures.ts needs no _generated/api.d.ts patch.

import { ActionCtx, MutationCtx, QueryCtx } from "./_generated/server";

// Clerk has no local users table, so tokenIdentifier ("issuer|subject") is
// the stable ownership key -- guidelines say prefer it over the bare
// `subject` claim.
export async function requireUser(
  ctx: QueryCtx | MutationCtx | ActionCtx,
): Promise<string> {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw new Error("Not signed in");
  }
  return identity.tokenIdentifier;
}
