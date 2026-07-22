<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

<!-- convex-ai-end -->

## Backend conventions

- **Idempotent creation.** A mutation that creates something uniquely
  identifiable dedups on its key and returns an explicit outcome the UI can act
  on (e.g. `{ status: "joined" | "already" }`), rather than silently
  succeeding. Keep the check and the insert in the same mutation: Convex runs
  mutations transactionally, so check-then-insert is race-safe without locks.
  Pick the conflict behavior per case -- return a status (waitlist), throw
  (username clash), or no-op / merge. Do not build a shared "uniqueness
  engine"; each check is a few lines and reads clearly inline. Key on the field
  that is actually unique (email), not an incidental one (name).
