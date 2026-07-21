# Love Alarm proximity detection research

## Problem

Euno is a private memory layer for finding your way back to people you have met. The new multi-user direction asks whether Euno can add a quiet "someone relevant is nearby" superpower without turning into a social network, a feed, or a passive tracking product.

The Love Alarm idea is emotionally strong: a person opens Euno in a real-world moment and gets a calm signal that another opted-in person is near enough to matter. The hard part is not the UI; it is consent, browser constraints, and avoiding a feature that feels like stalking.

Constraints:

- Web/PWA first. No dependable native Bluetooth LE, background location, or iOS-level nearby discovery.
- Clerk identity is available in Convex as `identity.tokenIdentifier` through `requireUser`.
- Euno's aesthetic is private, non-loud, and content-first.
- Do not implement contact exchange or shared notes here.

## Options

### 1. Geohash heartbeats

Each user opts into a short-lived radar session. The browser requests location permission, computes a coarse geohash/cell client-side, and sends heartbeats to Convex. A query looks for other active users in adjacent cells and only returns mutual matches.

Pros:

- Closest to the drama-inspired "nearby" behavior.
- Works across rooms/events without manually sharing a code.
- Can later support "people from your memory are nearby" by matching known identity links.

Cons:

- Web location permission is high-friction and emotionally sensitive.
- PWA background behavior is unreliable; the app must stay open.
- Even coarse cells can feel creepy if Euno stores a movement trail.
- Requires careful cell sizing, neighboring-cell queries, TTL cleanup, and rate limiting.

Privacy fit: acceptable only if sessions are explicit, foreground-only, TTL-bound, and store coarse cell prefixes rather than coordinates. Not the first MVP.

### 2. Meet-code rooms

Two or more people intentionally join the same short code for a few minutes. Convex stores presence rows keyed by room code and user identity, with heartbeats and expiration. The UI says who else is present in that room, but does not exchange contact details.

Pros:

- Strong consent model: having the code is the opt-in moment.
- Web-friendly: no Bluetooth or geolocation required.
- Easy to explain in Euno's calm voice.
- Low backend risk: one high-churn presence table, bounded queries, short TTL.
- Creates a foundation for future proximity without shipping passive tracking now.

Cons:

- It detects intentional co-presence, not physical proximity by itself.
- Less magical than automatic radar.
- Needs a graceful code-sharing ceremony in the UI.

Privacy fit: best MVP fit. It turns Love Alarm into "open a quiet room together" instead of always-on sensing.

### 3. Mutual radar

Users turn on "available to be sensed" for a time window. Radar only rings when both people have opted into the same context: same event, same meet-code, or mutual contact graph. This can sit on top of either meet-code rooms or coarse geohash.

Pros:

- Preserves the magic while requiring mutual consent.
- Lets Euno become more useful once there is a user graph.
- Can restrict matches to people already remembered or explicitly relevant.

Cons:

- Needs a real identity/relevance model that Euno does not have yet.
- Easy to overbuild into social graph mechanics.
- Requires careful copy so "mutual" does not imply relationship scoring.

Privacy fit: good as the direction after meet-code rooms, not as the first release.

## Privacy model

Principles:

1. **Foreground, intentional, temporary.** Radar starts from a tap, stays visible, and expires quickly without heartbeats.
2. **No passive history.** Presence is operational data, not a memory. Store current session rows only; do not build timelines.
3. **Server-derived identity.** All writes derive the user from Clerk via `requireUser`; clients never pass user ids.
4. **Minimal peer disclosure.** The first skeleton returns a display label and last seen time, never peer `userId` values.
5. **No contact exchange.** Being nearby does not save a person, send a note, or create a shared artifact.
6. **High-churn isolation.** Presence lives outside `people` so heartbeats do not contend with private memories.

Data retention:

- Presence TTL: 2 minutes.
- Heartbeat interval: about 25 seconds while the panel is open.
- A future cron can delete expired rows in bounded batches; the query layer already ignores expired rows.

Threats to watch:

- Guessable public codes can be joined by strangers. Codes should be short for demos but generated with enough entropy before a real launch.
- Display names are user-entered and visible to room peers. Keep them short and avoid storing profile data.
- Geohash mode, if added, must avoid raw coordinates and should quantize client-side before upload.

## Recommended MVP

Ship **meet-code rooms** as the first Love Alarm MVP.

Experience:

1. On the home sky, a small "Love Alarm" glass pill sits secondary to search/capture.
2. Tapping it opens a quiet panel: room code, optional display name, "Start radar."
3. While active, Euno heartbeats presence for a few minutes.
4. The panel lists other opted-in people in the same room as calm presence: "Maya" or "Someone nearby."
5. "Stop radar" deletes the user's presence. If the app closes, presence expires quickly.

Why this MVP:

- It is implementable on web/PWA today.
- It makes consent legible.
- It does not require a social graph, location tracking, or native APIs.
- It gives Convex a reusable presence substrate for future mutual radar.

## Schema sketch

Implemented skeleton table:

```ts
loveAlarmPresence: {
  userId: string; // Clerk tokenIdentifier, server-derived
  roomCode: string; // normalized meet code
  displayName: string; // visible only to active room peers
  joinedAt: number;
  lastSeenAt: number;
  expiresAt: number;
}
  .index("by_userId_and_roomCode", ["userId", "roomCode"])
  .index("by_userId_and_expiresAt", ["userId", "expiresAt"])
  .index("by_roomCode_and_expiresAt", ["roomCode", "expiresAt"])
```

Future mutual-radar additions:

```ts
loveAlarmConsents: {
  userId: string;
  scope: "room" | "event" | "coarseCell";
  scopeKey: string;
  mode: "visible" | "mutualOnly";
  createdAt: number;
  expiresAt: number;
}

loveAlarmSignals: {
  userId: string;
  peerUserId: string; // never returned directly to clients
  scopeKey: string;
  signaledAt: number;
  expiresAt: number;
}
```

If geohash arrives later, store only a coarse `cellPrefix` and perhaps adjacent-cell denormalized rows. Do not store raw latitude/longitude unless there is a concrete product need and a separate privacy review.

## API sketch

Implemented skeleton:

```ts
loveAlarm.startPresence({
  roomCode: string,
  displayName?: string,
}) -> { roomCode: string, expiresAt: number }

loveAlarm.heartbeat({
  roomCode: string,
}) -> { roomCode: string, expiresAt: number }

loveAlarm.stopPresence({
  roomCode: string,
}) -> null

loveAlarm.nearby({
  roomCode: string,
}) -> {
  roomCode: string,
  peers: Array<{ displayName: string; lastSeenAt: number }>
}

loveAlarm.myPresence({}) -> Array<{
  roomCode: string;
  displayName: string;
  lastSeenAt: number;
  expiresAt: number;
}>
```

Future API:

- `startMutualRadar({ scope, scopeKey, visibility })`
- `stopMutualRadar({ scope, scopeKey })`
- `nearbyRelevant({ scope, scopeKey }) -> quiet signal count + matching remembered people`
- `cleanupExpiredPresence()` as a bounded internal mutation scheduled by cron

## Risks

- **False sense of proximity.** Meet-code rooms are co-presence by consent, not sensor proximity. Copy must say "room" and "radar" carefully.
- **Creep factor.** Any automatic version must be mutual, visible, and short-lived.
- **Notification temptation.** Loud push alerts would violate Euno's calm posture. Prefer in-app signal while the panel is open.
- **Guessable rooms.** Demo-friendly codes are easy to join. Production should generate random codes and possibly require both parties to confirm.
- **Convex churn.** Heartbeats can create write load. Keep TTL short, table isolated, and rate limits conservative.
- **Identity mismatch.** Euno does not yet know how one user's account maps to another user's private `people` record. Do not infer that from display names.

## Implement next checklist

- Add bounded cleanup for expired `loveAlarmPresence` rows.
- Generate stronger default room codes client-side.
- Decide whether display names should come from Clerk identity, a local profile, or one-off room labels.
- Add a "mutual only" mode once Euno has a deliberate identity/relevance model.
- If exploring geohash, prototype coarse client-side quantization and adjacent-cell querying behind a separate privacy review.
