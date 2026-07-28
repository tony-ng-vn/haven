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

## Changelog conventions

`CHANGELOG.md` is updated as part of the change that prompted it, not as a
separate cleanup pass. Skip it only for changes a user could never notice:
refactors, test-only work, and internal tooling.

- **Categories** are these five, and only the ones a change actually touched:
  **iOS** (`ios/`), **Web** (`src/`), **Backend** (`convex/`), **CI**
  (`.github/`), **Docs** (`docs/`, `README.md`, and this file). They mirror
  how the repo splits, so the area a bullet belongs under is never a
  judgement call.
- **Bullets describe what changed for someone using Haven**, not what the
  commit did. "Haven can now tell whether someone is a paying subscriber"
  beats "add subscriptions table and webhook handler". If a change is only
  legible as architecture, say what it makes possible.
- **Entry shape:** `## vX.Y.Z`, the date on its own line, one `**Category**`
  subheading per area, plain-language bullets under each, then `---`. Newest
  entry at the top.
- **Version bumps** follow the newest entry: patch for fixes and docs, minor
  for new features or visible behavior changes, major for breaking changes.
  Keep `package.json` in sync.
- **`package.json` and the iOS `MARKETING_VERSION` in `ios/project.yml` are
  deliberately not kept in lockstep.** `package.json` versions the codebase
  and drives this file; `MARKETING_VERSION` versions what people install from
  the App Store and moves only when an iOS build ships. A backend-only
  release must not bump the App Store version, or it advertises an iOS
  release that never happened. Edit `ios/project.yml`, never the generated
  `.xcodeproj`.
