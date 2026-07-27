import {
  internalAction,
  internalMutation,
  internalQuery,
  ActionCtx,
  MutationCtx,
} from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { embedText } from "./openaiClient";

// A person's memories are derived from their context, which every write path
// clamps to 4000 characters -- but a person edited over years accumulates
// lines faster than the blob does, because nothing is ever deleted. The cap
// is what keeps the dedupe read and the delete cascade bounded.
export const MAX_MEMORIES_PER_PERSON = 200;

// Same schedule people.embed uses: index 0 is the delay before retry attempt
// 1, index 1 before attempt 2, then we give up.
const EMBED_RETRY_DELAYS_MS = [30_000, 5 * 60_000];

// The embeddings request has its own size ceiling, and one memory line can be
// the whole 4000-character context blob.
const MAX_EMBED_INPUT_LENGTH = 8000;

// Smaller than people.ts's 500: this page also schedules one embed action per
// line it inserts, so a large page would queue thousands of paid calls in one
// transaction.
const BACKFILL_PAGE_SIZE = 100;

// How many unembedded rows one sweep pass repairs.
const EMBED_SWEEP_LIMIT = 200;

// appendContext has always joined entries with a newline, so splitting on one
// is faithful to the boundaries the user actually wrote -- which is also what
// makes the migration in backfillMemories the same operation as a live write.
function splitMemoryLines(context: string | undefined): string[] {
  if (context === undefined) {
    return [];
  }
  return context
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line !== "");
}

// Additive on purpose. A note the user later edits away keeps its memory row:
// the display copy is what they curate, and forgetting a thing they once
// wrote is the one failure this whole plan exists to prevent. The cost is
// that a typo fixed in the note leaves the typo'd line searchable.
export async function syncMemories(
  ctx: MutationCtx,
  args: {
    userId: string;
    personId: Id<"people">;
    context: string | undefined;
    createdAt: number;
  },
): Promise<void> {
  const lines = splitMemoryLines(args.context);
  if (lines.length === 0) {
    return;
  }
  const existing = await ctx.db
    .query("memories")
    .withIndex("by_person", (q) => q.eq("personId", args.personId))
    .take(MAX_MEMORIES_PER_PERSON);
  const seen = new Set(existing.map((memory) => memory.text));
  let room = MAX_MEMORIES_PER_PERSON - existing.length;
  for (const text of lines) {
    if (room === 0) {
      return;
    }
    if (seen.has(text)) {
      continue;
    }
    seen.add(text);
    room--;
    const memoryId = await ctx.db.insert("memories", {
      userId: args.userId,
      personId: args.personId,
      text,
      createdAt: args.createdAt,
    });
    await ctx.scheduler.runAfter(0, internal.memories.embed, { memoryId });
  }
}

// Bounded by the same cap the insert path enforces, so one take is the whole
// set. Orphaned rows would keep matching in the vector index for a person the
// user deleted.
export async function deleteMemories(
  ctx: MutationCtx,
  personId: Id<"people">,
): Promise<void> {
  const rows = await ctx.db
    .query("memories")
    .withIndex("by_person", (q) => q.eq("personId", personId))
    .take(MAX_MEMORIES_PER_PERSON);
  for (const row of rows) {
    await ctx.db.delete("memories", row._id);
  }
}

// ------------------------------------------------------------- embeddings

export const getMemoryInternal = internalQuery({
  args: { id: v.id("memories") },
  handler: async (ctx, args) => {
    return await ctx.db.get("memories", args.id);
  },
});

export const saveMemoryEmbedding = internalMutation({
  args: {
    id: v.id("memories"),
    embedding: v.array(v.float64()),
    embeddedText: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const memory = await ctx.db.get("memories", args.id);
    if (memory === null) {
      return null;
    }
    await ctx.db.patch("memories", args.id, {
      embedding: args.embedding,
      embeddedText: args.embeddedText,
    });
    return null;
  },
});

// Shared by the embed action and the sweep (guidelines: do not call an action
// from an action in the same runtime; share a helper instead).
async function embedMemory(
  ctx: ActionCtx,
  memoryId: Id<"memories">,
): Promise<void> {
  const memory: Doc<"memories"> | null = await ctx.runQuery(
    internal.memories.getMemoryInternal,
    { id: memoryId },
  );
  if (memory === null) {
    return;
  }
  // The line itself is the embed input: that is the whole point of a memory
  // row, so no surrounding card fields are mixed back in.
  const text = memory.text.slice(0, MAX_EMBED_INPUT_LENGTH);
  if (memory.embedding !== undefined && memory.embeddedText === text) {
    return;
  }
  const embedding = await embedText(text);
  await ctx.runMutation(internal.memories.saveMemoryEmbedding, {
    id: memoryId,
    embedding,
    embeddedText: text,
  });
}

export const embed = internalAction({
  args: { memoryId: v.id("memories"), attempt: v.optional(v.number()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const attempt = args.attempt ?? 0;
    try {
      await embedMemory(ctx, args.memoryId);
    } catch (error) {
      const delayMs = EMBED_RETRY_DELAYS_MS[attempt];
      if (delayMs === undefined) {
        // Out of retries: log and give up rather than throw, so one stuck
        // line can never surface as an unhandled action failure. The daily
        // sweep below picks it up.
        console.error(
          `memories.embed: giving up on ${args.memoryId} after ${attempt + 1} attempts`,
          error,
        );
        return null;
      }
      await ctx.scheduler.runAfter(delayMs, internal.memories.embed, {
        memoryId: args.memoryId,
        attempt: attempt + 1,
      });
    }
    return null;
  },
});

// Bounded honestly: a full scan of the table, stopping at EMBED_SWEEP_LIMIT
// matches. At personal-network scale (hundreds of people, thousands of lines)
// that is one cheap read; if it ever is not, the upgrade is a persisted sweep
// cursor like captures.sweepOrphanedUploads keeps in sweepState.
export const listMissingMemoryEmbeddings = internalQuery({
  args: {},
  returns: v.array(v.id("memories")),
  handler: async (ctx) => {
    const rows = await ctx.db
      .query("memories")
      .filter((q) => q.eq(q.field("embedding"), undefined))
      .take(EMBED_SWEEP_LIMIT);
    return rows.map((row) => row._id);
  },
});

// Self-heals memories whose embed action failed (or whose scheduled retry got
// lost), and the way the migration below gets its rows embedded. Run by hand
// with: npx convex run memories:backfillMemoryEmbeddings
export const backfillMemoryEmbeddings = internalAction({
  args: {},
  returns: v.number(),
  handler: async (ctx) => {
    const ids: Array<Id<"memories">> = await ctx.runQuery(
      internal.memories.listMissingMemoryEmbeddings,
      {},
    );
    let embedded = 0;
    for (const memoryId of ids) {
      // One bad row must not abort the sweep: this runs unattended from the
      // daily cron, and an aborted loop would re-fail identically every day
      // while every row behind the bad one stays unembedded.
      try {
        await embedMemory(ctx, memoryId);
        embedded++;
      } catch (error) {
        console.error(`backfillMemoryEmbeddings: skipping ${memoryId}`, error);
      }
    }
    return embedded;
  },
});

// --------------------------------------------------------------- migration

// One-off maintenance: people written before this table existed carry their
// whole history in the context blob, which is invisible to per-memory
// retrieval until split out. Paged rather than a single batch because a
// person whose memories are missing is a person the search silently forgets,
// so "done" has to mean it. Run with:
// npx convex run memories:backfillMemories '{}'
// and re-run with '{"cursor": "<cursor>"}' until isDone, then run
// memories:backfillMemoryEmbeddings until it returns 0.
//
// Idempotent by skipping any person who already has rows, rather than by
// deduping line by line: a person whose lines were already split is done,
// however the live write paths have edited them since.
export const backfillMemories = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())) },
  returns: v.object({
    patched: v.number(),
    skipped: v.number(),
    isDone: v.boolean(),
    cursor: v.string(),
  }),
  handler: async (ctx, args) => {
    const page = await ctx.db.query("people").paginate({
      numItems: BACKFILL_PAGE_SIZE,
      cursor: args.cursor ?? null,
    });
    let patched = 0;
    let skipped = 0;
    for (const person of page.page) {
      const lines = splitMemoryLines(person.context);
      if (lines.length === 0) {
        continue;
      }
      const existing = await ctx.db
        .query("memories")
        .withIndex("by_person", (q) => q.eq("personId", person._id))
        .first();
      if (existing !== null) {
        skipped++;
        continue;
      }
      for (const text of lines.slice(0, MAX_MEMORIES_PER_PERSON)) {
        // No embed scheduled here: a page of 100 people would queue hundreds
        // of paid calls in one transaction. backfillMemoryEmbeddings does it,
        // at a pace the operator controls.
        await ctx.db.insert("memories", {
          userId: person.userId,
          personId: person._id,
          text,
          createdAt: person.updatedAt,
        });
      }
      patched++;
    }
    return {
      patched,
      skipped,
      isDone: page.isDone,
      cursor: page.continueCursor,
    };
  },
});

// ------------------------------------------------------- semantic search

// Hydration for the action's memory hits: which person each matching line
// belongs to, and the line itself, which is the evidence the result shows.
// Safe without an auth check -- internal only, and the ids come from a vector
// search already filtered to the caller's userId.
export const fetchMemoryOwners = internalQuery({
  args: { ids: v.array(v.id("memories")) },
  returns: v.array(
    v.object({
      _id: v.id("memories"),
      personId: v.id("people"),
      text: v.string(),
    }),
  ),
  handler: async (ctx, args) => {
    const rows: Array<{
      _id: Id<"memories">;
      personId: Id<"people">;
      text: string;
    }> = [];
    for (const id of args.ids) {
      const memory = await ctx.db.get("memories", id);
      if (memory !== null) {
        rows.push({
          _id: memory._id,
          personId: memory.personId,
          text: memory.text,
        });
      }
    }
    return rows;
  },
});
