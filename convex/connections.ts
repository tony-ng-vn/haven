// The teardown shared by every way a connection can end. Its own module
// because both sides need it -- profiles.disconnect ends one deliberately,
// people.deletePerson ends one as a side effect of throwing the contact away
// -- and neither of those files should have to import the other.

import { MutationCtx } from "./_generated/server";
import { Doc, Id } from "./_generated/dataModel";

// The edge either side of a connection. Bounded: a person row can name at
// most one connection, from whichever side the caller happens to be on.
async function findEdge(
  ctx: MutationCtx,
  userId: string,
  personId: Id<"people">,
): Promise<Doc<"connections"> | null> {
  return (
    (await ctx.db
      .query("connections")
      .withIndex("by_userAId_and_personAId", (q) =>
        q.eq("userAId", userId).eq("personAId", personId),
      )
      .unique()) ??
    (await ctx.db
      .query("connections")
      .withIndex("by_userBId_and_personBId", (q) =>
        q.eq("userBId", userId).eq("personBId", personId),
      )
      .unique())
  );
}

// Ends the connection this person row belongs to, if any, and reports
// whether there was one.
//
// An edge is mutual, so ending it ends it for both: each side keeps their
// contact as the frozen snapshot they own, like a phone contact, and neither
// keeps rendering a card that will no longer move. The shared note goes with
// the edge, because it was written by two people, is only reachable through
// the edge, and would otherwise be silently reattached to a conversation
// neither side asked for if the two ever connected again.
//
// havenContactUserId deliberately survives here, unlike in the account-purge
// collapse: the peer still exists, and that key is what lets a later
// reconnection thaw this row instead of making a second contact for the same
// human. Account deletion clears it because the leaving user's identity goes
// with them.
export async function endConnection(
  ctx: MutationCtx,
  userId: string,
  personId: Id<"people">,
  now: number,
): Promise<boolean> {
  const edge = await findEdge(ctx, userId, personId);
  if (edge === null) {
    return false;
  }
  const notes = await ctx.db
    .query("sharedNotes")
    .withIndex("by_connectionId", (q) => q.eq("connectionId", edge._id))
    .collect();
  for (const note of notes) {
    await ctx.db.delete("sharedNotes", note._id);
  }
  await ctx.db.delete("connections", edge._id);
  for (const id of [edge.personAId, edge.personBId]) {
    // The other side's row can already be gone -- they deleted the contact,
    // or this call is the delete that is about to remove ours.
    if ((await ctx.db.get("people", id)) !== null) {
      await ctx.db.patch("people", id, { connectionEndedAt: now });
    }
  }
  return true;
}
