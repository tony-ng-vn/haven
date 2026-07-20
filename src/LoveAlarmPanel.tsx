import { useEffect, useState, type FormEvent } from "react";
import { useMutation, useQuery } from "convex/react";
import type { FunctionReturnType } from "convex/server";
import { api } from "../convex/_generated/api";

type NearbyResult = FunctionReturnType<typeof api.loveAlarm.nearby>;

const HEARTBEAT_MS = 25_000;

function defaultRoomCode(): string {
  return new Date().toISOString().slice(0, 10).replace(/-/g, "");
}

export function LoveAlarmPanel({
  onMeetUsername,
}: {
  onMeetUsername?: (username: string) => void;
}) {
  const startPresence = useMutation(api.loveAlarm.startPresence);
  const heartbeat = useMutation(api.loveAlarm.heartbeat);
  const stopPresence = useMutation(api.loveAlarm.stopPresence);
  const [open, setOpen] = useState(false);
  const [roomCode, setRoomCode] = useState(defaultRoomCode);
  const [displayName, setDisplayName] = useState("");
  const [joinedRoom, setJoinedRoom] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const nearby = useQuery(
    api.loveAlarm.nearby,
    joinedRoom === null ? "skip" : { roomCode: joinedRoom },
  );

  useEffect(() => {
    if (joinedRoom === null) return;
    const timer = window.setInterval(() => {
      heartbeat({ roomCode: joinedRoom }).catch(() => {
        setJoinedRoom(null);
        setError("Radar paused. Join the room again when you are ready.");
      });
    }, HEARTBEAT_MS);
    return () => window.clearInterval(timer);
  }, [heartbeat, joinedRoom]);

  async function handleJoin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    setError(null);
    try {
      const started = await startPresence({
        roomCode,
        displayName: displayName === "" ? undefined : displayName,
      });
      setJoinedRoom(started.roomCode);
      setRoomCode(started.roomCode);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not start radar");
    } finally {
      setSaving(false);
    }
  }

  async function handleStop() {
    if (joinedRoom === null) return;
    const room = joinedRoom;
    setJoinedRoom(null);
    setError(null);
    await stopPresence({ roomCode: room }).catch(() => {
      setError("Could not stop radar. It will expire shortly.");
    });
  }

  const peers: NearbyResult["peers"] = nearby?.peers ?? [];

  if (!open) {
    return (
      <div className="love-alarm">
        <button
          className="love-alarm-toggle"
          type="button"
          onClick={() => setOpen(true)}
        >
          Love Alarm
        </button>
      </div>
    );
  }

  return (
    <section className="love-alarm love-alarm-card" aria-labelledby="love-alarm-title">
      <div className="love-alarm-head">
        <div>
          <p className="sky-label">opt-in radar</p>
          <h2 id="love-alarm-title">Love Alarm</h2>
        </div>
        <button
          className="love-alarm-close"
          type="button"
          aria-label="Close Love Alarm"
          onClick={() => setOpen(false)}
        >
          Close
        </button>
      </div>

      {joinedRoom === null ? (
        <form className="love-alarm-form" onSubmit={handleJoin}>
          <p className="love-alarm-copy">
            Share a small code with someone nearby. Euno listens only while this room
            is open.
          </p>
          <label>
            <span>Room code</span>
            <input
              className="love-alarm-input"
              value={roomCode}
              onChange={(event) => setRoomCode(event.target.value)}
              autoCapitalize="characters"
              autoComplete="off"
            />
          </label>
          <label>
            <span>Display name</span>
            <input
              className="love-alarm-input"
              value={displayName}
              onChange={(event) => setDisplayName(event.target.value)}
              placeholder="Uses your @username if set"
              autoComplete="off"
            />
          </label>
          {error !== null && <p className="love-alarm-error">{error}</p>}
          <button className="love-alarm-primary" type="submit" disabled={saving}>
            {saving ? "Starting" : "Start radar"}
          </button>
        </form>
      ) : (
        <div className="love-alarm-active">
          <p className="love-alarm-copy">
            Room <strong>{joinedRoom}</strong> is open for the next few minutes.
          </p>
          {nearby === undefined ? (
            <p className="love-alarm-muted">Listening quietly...</p>
          ) : peers.length === 0 ? (
            <p className="love-alarm-muted">No one else has joined this room yet.</p>
          ) : (
            <ul className="love-alarm-peers" aria-label="Nearby people">
              {peers.map((peer) => (
                <li key={`${peer.displayName}-${peer.lastSeenAt}-${peer.username ?? ""}`}>
                  <span className="love-alarm-dot" aria-hidden="true" />
                  <span className="love-alarm-peer-name">{peer.displayName}</span>
                  {peer.username !== undefined && onMeetUsername !== undefined && (
                    <button
                      type="button"
                      className="love-alarm-meet"
                      onClick={() => {
                        const username = peer.username;
                        if (username !== undefined) onMeetUsername(username);
                      }}
                    >
                      Meet
                    </button>
                  )}
                </li>
              ))}
            </ul>
          )}
          {error !== null && <p className="love-alarm-error">{error}</p>}
          <button className="love-alarm-secondary" type="button" onClick={handleStop}>
            Stop radar
          </button>
        </div>
      )}
    </section>
  );
}
