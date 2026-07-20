# Meet · Love Alarm · Shared Notes Synthesis

Date: 2026-07-20
Status: Integrated MVP on atlas

## What we explored

Three parallel worktrees each owned one idea:

| Idea | Verdict | Ship shape |
| --- | --- | --- |
| Love Alarm proximity | Prefer intentional meet-code rooms over GPS/BLE | Opt-in room + short TTL presence |
| Mutual note sync | Keep `people.context` private; share a pair-scoped note | `connections` + `sharedNotes`, last-write-wins |
| NameDrop-style contact sync | Instant mutual exchange with local confirmation | Username profiles + Meet widget |

## How they fit together

```
Claim @username
      │
      ▼
┌─────────────┐     room code      ┌──────────────┐
│ Love Alarm  │ ─────────────────▶ │ see peer @x  │
│ (detect)    │                    │ tap Meet     │
└─────────────┘                    └──────┬───────┘
                                          │
                                          ▼
                               ┌────────────────────┐
                               │ Euno Meet exchange │
                               │ private people ×2  │
                               │ connections row    │
                               └─────────┬──────────┘
                                         │
                                         ▼
                               ┌────────────────────┐
                               │ Shared notes on    │
                               │ PersonDetail       │
                               └────────────────────┘
```

1. **Detect** — Love Alarm is only a quiet radar. Two people share a short-lived room code; no geolocation, no always-on tracking.
2. **Exchange** — Meet is NameDrop-for-web: say or tap the username, confirm once, both get a private contact. Meet also writes the `connections` row that unlocks shared notes.
3. **Remember together** — Shared notes live on the mutual connection. Private context stays private.

## Privacy stance

Euno remains a personal memory layer first. Multi-user surface is opt-in and in-person:

- Usernames exist only to exchange, not to browse a directory.
- Presence expires in minutes and is room-scoped.
- Shared notes require an explicit Meet (or equivalent mutual connection).
- No feeds, follows, or activity streams.

## Files

- Specs: `docs/superpowers/specs/2026-07-20-{love-alarm,mutual-note-sync,namedrop-contact-sync}-research.md`
- Backend: `convex/{profiles,loveAlarm,sharedNotes}.ts`, `convex/schema.ts`
- UI: Meet sheet in `src/SearchAdd.tsx`, `src/LoveAlarmPanel.tsx`, shared notes in `src/PersonDetail.tsx`
