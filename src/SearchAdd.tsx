import { useQuery, useMutation, useAction } from "convex/react";
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type FormEvent,
} from "react";
import type { FunctionReturnType } from "convex/server";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";
import { formatMonthYear, type PersonSnapshot } from "./lib";
import { atlasLayout, buildCluster, buildDust } from "./sky";
import { composeAtlasField } from "./lib";
import { LoveAlarmPanel } from "./LoveAlarmPanel";

type SemanticResults = FunctionReturnType<typeof api.people.semanticSearch>;
type MeetExchangeResult = FunctionReturnType<typeof api.profiles.meetExchange>;

type MeetSpeechRecognitionEvent = Event & {
  results: {
    [index: number]: {
      [index: number]: { transcript: string };
    };
  };
};

type MeetSpeechRecognition = {
  lang: string;
  interimResults: boolean;
  maxAlternatives: number;
  start: () => void;
  stop: () => void;
  onresult: ((event: MeetSpeechRecognitionEvent) => void) | null;
  onerror: (() => void) | null;
  onend: (() => void) | null;
};

type WindowWithSpeech = Window & {
  SpeechRecognition?: new () => MeetSpeechRecognition;
  webkitSpeechRecognition?: new () => MeetSpeechRecognition;
};

// Mirrors the backend RESULT_LIMIT: the home query returns at most this many
// recent people, so the sky renders at most this many clusters.
const RESULT_LIMIT = 20;

// Below this viewport width the clusters and labels shrink so everything stays
// tappable on a phone (decision 12).
const MOBILE_MAX_WIDTH = 480;

// The dust is dealt into this many group-shimmer layers: each layer runs one
// slow opacity breathe for all its stars instead of ~80 per-node twinkles.
const DUST_SHIMMER_LAYERS = 3;

function SearchIcon() {
  return (
    <svg
      className="search-icon"
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
    >
      <circle cx="10.5" cy="10.5" r="6.5" stroke="currentColor" strokeWidth="2" />
      <path
        d="m15.5 15.5 5 5"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  );
}

function ClearIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M6 6l12 12M18 6 6 18"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinecap="round"
      />
    </svg>
  );
}

function normalizeMeetUsername(raw: string) {
  return raw.trim().replace(/^@+/, "").toLowerCase();
}

// Track the live viewport so the spiral layout and dust field fill the whole
// screen and reflow on resize (the sky is full-bleed, not inside .app-main).
function useViewport() {
  const [size, setSize] = useState(() => ({
    w: typeof window === "undefined" ? 1024 : window.innerWidth,
    h: typeof window === "undefined" ? 768 : window.innerHeight,
  }));
  useEffect(() => {
    const onResize = () =>
      setSize({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);
  return size;
}

// The Atlas home: the signed-in landing is now a full-viewport shared sky where
// each remembered person is their own small constellation with their name
// beneath it. Kept as SearchAdd (filename + export) to minimize churn; App.tsx
// still wires it as the "search" screen.
export function SearchAdd({
  query,
  onQueryChange,
  onOpen,
  onOpenCapture,
  morphId,
}: {
  query: string;
  onQueryChange: (query: string) => void;
  onOpen: (person: PersonSnapshot) => void;
  onOpenCapture: () => void;
  morphId: Id<"people"> | null;
}) {
  // The recent-first field of people IS the sky (empty query). Held stable so
  // typing dims/lights clusters without ever reordering or removing them.
  const people = useQuery(api.people.searchPeople, { query: "" });
  // The live name search drives which clusters stay lit. Two subscriptions to
  // the same function; when the query is empty they dedupe to one.
  const nameMatches = useQuery(api.people.searchPeople, { query });
  const addPerson = useMutation(api.people.addPerson);
  const profile = useQuery(api.profiles.getMyProfile, {});
  const setUsername = useMutation(api.profiles.setUsername);
  const meetExchange = useMutation(api.profiles.meetExchange);
  const semanticSearch = useAction(api.people.semanticSearch);
  const [adding, setAdding] = useState(false);
  const [semantic, setSemantic] = useState<SemanticResults>([]);
  const [meetOpen, setMeetOpen] = useState(false);
  const [usernameDraft, setUsernameDraft] = useState("");
  const [savingUsername, setSavingUsername] = useState(false);
  const [meetUsername, setMeetUsername] = useState("");
  const [meetError, setMeetError] = useState<string | null>(null);
  const [meetStatus, setMeetStatus] = useState<string | null>(null);
  const [exchanging, setExchanging] = useState(false);
  const [lastMeet, setLastMeet] = useState<MeetExchangeResult | null>(null);
  const [listening, setListening] = useState(false);
  const inputRef = useRef<HTMLInputElement | null>(null);
  const speechRef = useRef<MeetSpeechRecognition | null>(null);

  const trimmed = query.trim();
  const meetLookupUsername = normalizeMeetUsername(meetUsername);
  const meetLookup = useQuery(
    api.profiles.lookupByUsername,
    meetLookupUsername.length >= 3 ? { username: meetLookupUsername } : "skip",
  );

  // Meaning-based matches arrive quietly beside the instant name search:
  // debounced, stale-guarded, and silent on failure.
  useEffect(() => {
    if (trimmed.length < 3) {
      setSemantic([]);
      return;
    }
    let cancelled = false;
    const timer = setTimeout(() => {
      semanticSearch({ query: trimmed })
        .then((found) => {
          if (!cancelled) setSemantic(found);
        })
        .catch(() => {
          if (!cancelled) setSemantic([]);
        });
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [trimmed, semanticSearch]);

  useEffect(() => {
    return () => speechRef.current?.stop();
  }, []);

  const fieldLoaded = people !== undefined;
  const searchLoaded = nameMatches !== undefined;
  const profileLoaded = profile !== undefined;
  const canUseSpeech =
    typeof window !== "undefined" &&
    (("SpeechRecognition" in window) || ("webkitSpeechRecognition" in window));

  // Only the first paint (no field yet) gets a delayed status, and only once
  // loading has run long enough to be worth acknowledging -- fast answers
  // should still render with no flash at all.
  const [showLoading, setShowLoading] = useState(false);
  useEffect(() => {
    if (fieldLoaded) {
      setShowLoading(false);
      return;
    }
    const timer = setTimeout(() => setShowLoading(true), 300);
    return () => clearTimeout(timer);
  }, [fieldLoaded]);

  const { w, h } = useViewport();
  const mobile = w < MOBILE_MAX_WIDTH;
  const boxW = mobile ? 96 : 120;
  const boxH = mobile ? 72 : 92;
  const labelH = mobile ? 40 : 46;

  const list = useMemo(() => people ?? [], [people]);

  const dust = useMemo(() => buildDust(), []);

  // The rendered field: the stable recent people first (their spiral spots
  // never move), plus any search match not already among them, materializing
  // at the spiral's outer edge. Without this, an off-field match could never
  // be opened -- and "Add" would offer to duplicate them.
  // Typed to the snapshot shape all three sources share (semantic results
  // carry a score but no screenshotId/updatedAt) -- the atlas only needs
  // what PersonSnapshot guarantees.
  const field = useMemo<PersonSnapshot[]>(
    () =>
      trimmed === ""
        ? list
        : composeAtlasField<PersonSnapshot>(list, nameMatches ?? [], semantic),
    [trimmed, list, nameMatches, semantic],
  );

  // One cluster figure per person. Rebuilds only when the field composition
  // changes (a keystroke that surfaces no new person reuses the memo).
  const clusters = useMemo(
    () => field.map((p) => buildCluster(p.name, undefined, { width: boxW, height: boxH })),
    [field, boxW, boxH],
  );

  const positions = useMemo(
    () => atlasLayout(field.length, w, h, { boxW, boxH, labelH }),
    [field.length, w, h, boxW, boxH, labelH],
  );

  const nameMatchIds = useMemo(
    () => new Set((nameMatches ?? []).map((p) => p._id)),
    [nameMatches],
  );
  const semanticIds = useMemo(
    () => new Set(semantic.map((m) => m._id)),
    [semantic],
  );

  // A cluster is lit when nothing is typed, or its person matches the typed
  // name, or its person matches by meaning. Until the name search answers we
  // keep everyone lit so the sky never flashes dim then bright.
  const isLit = (id: Id<"people">) =>
    trimmed === "" || !searchLoaded || nameMatchIds.has(id) || semanticIds.has(id);
  // Lit by meaning alone (not by name): earns the amber "memory" halo + tag.
  const isMemory = (id: Id<"people">) =>
    trimmed !== "" &&
    searchLoaded &&
    !nameMatchIds.has(id) &&
    semanticIds.has(id);

  const hasExact = (nameMatches ?? []).some(
    (p) => p.name.toLowerCase() === trimmed.toLowerCase(),
  );
  // No exact name match -> offer to add the typed name as a new star.
  const showAdd = searchLoaded && trimmed !== "" && !hasExact;

  const isEmpty = fieldLoaded && list.length === 0;
  const atCap = fieldLoaded && list.length >= RESULT_LIMIT;

  async function handleAdd() {
    if (adding || trimmed === "") return;
    setAdding(true);
    try {
      const id = await addPerson({ name: trimmed });
      onOpen({ _id: id, name: trimmed, _creationTime: Date.now() });
    } finally {
      setAdding(false);
    }
  }

  async function handleSaveUsername() {
    if (savingUsername) return;
    setSavingUsername(true);
    setMeetError(null);
    setMeetStatus(null);
    try {
      const saved = await setUsername({ username: usernameDraft });
      setUsernameDraft(saved.username);
      setMeetStatus(`You are @${saved.username}.`);
    } catch (error) {
      setMeetError(error instanceof Error ? error.message : "Could not save username");
    } finally {
      setSavingUsername(false);
    }
  }

  async function handleMeetExchange() {
    if (exchanging || meetLookupUsername === "") return;
    setExchanging(true);
    setMeetError(null);
    setMeetStatus(null);
    setLastMeet(null);
    try {
      const exchanged = await meetExchange({ username: meetLookupUsername });
      setLastMeet(exchanged);
      setMeetUsername("");
      setMeetStatus(`You and @${exchanged.peerUsername} are in each other's sky.`);
    } catch (error) {
      setMeetError(error instanceof Error ? error.message : "Could not exchange");
    } finally {
      setExchanging(false);
    }
  }

  function startSpeech() {
    const speechWindow = window as WindowWithSpeech;
    const Recognition =
      speechWindow.SpeechRecognition ?? speechWindow.webkitSpeechRecognition;
    if (Recognition === undefined || listening) return;
    const recognition = new Recognition();
    speechRef.current = recognition;
    recognition.lang = "en-US";
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;
    recognition.onresult = (event) => {
      const transcript = event.results[0]?.[0]?.transcript;
      if (transcript !== undefined) {
        setMeetUsername(transcript);
      }
    };
    recognition.onerror = () => {
      setMeetError("Could not hear a username");
    };
    recognition.onend = () => {
      setListening(false);
      speechRef.current = null;
    };
    setMeetError(null);
    setListening(true);
    recognition.start();
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (showAdd) void handleAdd();
  }

  return (
    <form className="atlas" onSubmit={handleSubmit}>
      <div className="atlas-space" aria-hidden="true" />

      {/* One shared, faint dust field behind every cluster: static stars split
          across a few slow group-shimmer layers so the whole field breathes as
          one. The viewBox matches the pixel size so circles stay round. */}
      <svg
        className="atlas-dust"
        viewBox={`0 0 ${w} ${h}`}
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        {Array.from({ length: DUST_SHIMMER_LAYERS }, (_, l) => (
          <g key={l} className={`sky-shimmer sky-shimmer-${l}`}>
            {dust.map((s, i) =>
              i % DUST_SHIMMER_LAYERS === l ? (
                <circle
                  key={i}
                  style={
                    {
                      "--hi": s.hi.toFixed(2),
                      "--mid": ((s.hi + s.lo) / 2).toFixed(2),
                    } as CSSProperties
                  }
                  cx={(s.x * w).toFixed(1)}
                  cy={(s.y * h).toFixed(1)}
                  r={s.r.toFixed(2)}
                  fill="#fff"
                />
              ) : null,
            )}
          </g>
        ))}
      </svg>

      {/* Search floats top-center under the frosted header. Held back until
          the field has loaded so the first paint is dust alone (decision 8). */}
      {fieldLoaded && (
      <div className="atlas-search">
        <div className="atlas-pill">
          <SearchIcon />
          <input
            ref={inputRef}
            className="atlas-input"
            placeholder="Search a name, or type a new one"
            aria-label="Search people"
            value={query}
            onChange={(e) => onQueryChange(e.target.value)}
            autoFocus
            autoCapitalize="words"
            autoComplete="off"
            spellCheck={false}
            enterKeyHint="go"
          />
          {query !== "" && (
            <button
              type="button"
              className="atlas-clear"
              aria-label="Clear search"
              onClick={() => {
                onQueryChange("");
                inputRef.current?.focus();
              }}
            >
              <ClearIcon />
            </button>
          )}
        </div>

        {showAdd && (
          <button
            type="submit"
            className="atlas-add"
            disabled={adding}
          >
            {adding && <span className="spinner" aria-hidden="true" />}
            {`Add "${trimmed}" to your sky`}
          </button>
        )}
      </div>
      )}

      {fieldLoaded && (
        <button
          type="button"
          className="atlas-meet-fab"
          onClick={() => {
            setMeetOpen((open) => !open);
            setMeetError(null);
            setMeetStatus(null);
          }}
          aria-expanded={meetOpen}
        >
          {meetOpen ? "Close Meet" : "Meet"}
        </button>
      )}

      {fieldLoaded && meetOpen && (
        <section className="meet-sheet" aria-label="Meet by Euno username">
          <div className="meet-sheet-head">
            <span className="sky-label">euno meet</span>
            <button
              type="button"
              className="meet-close"
              onClick={() => setMeetOpen(false)}
              aria-label="Close Meet"
            >
              <ClearIcon />
            </button>
          </div>
          <h2 className="meet-title">Exchange in person</h2>
          <p className="meet-copy">
            Stand together, say the other person's Euno username, then confirm.
            Euno privately adds each of you to the other's sky.
          </p>

          {!profileLoaded && (
            <p className="meet-muted" role="status">
              reading your username
            </p>
          )}

          {profileLoaded && profile === null && (
            <div className="meet-stack">
              <label className="meet-label" htmlFor="meet-username-setup">
                Your Euno username
              </label>
              <div className="meet-input-row">
                <span className="meet-at">@</span>
                <input
                  id="meet-username-setup"
                  className="meet-input"
                  value={usernameDraft}
                  onChange={(e) => setUsernameDraft(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      void handleSaveUsername();
                    }
                  }}
                  autoCapitalize="none"
                  autoComplete="off"
                  spellCheck={false}
                  placeholder="maya_7"
                />
              </div>
              <button
                type="button"
                className="atlas-add meet-primary"
                disabled={savingUsername}
                onClick={() => void handleSaveUsername()}
              >
                {savingUsername && <span className="spinner" aria-hidden="true" />}
                Save username
              </button>
            </div>
          )}

          {profileLoaded && profile !== null && (
            <div className="meet-stack">
              <p className="meet-muted">You are @{profile.username}</p>
              <label className="meet-label" htmlFor="meet-peer-username">
                Their username
              </label>
              <div className="meet-input-row">
                <span className="meet-at">@</span>
                <input
                  id="meet-peer-username"
                  className="meet-input"
                  value={meetUsername}
                  onChange={(e) => {
                    setMeetUsername(e.target.value);
                    setMeetStatus(null);
                    setMeetError(null);
                    setLastMeet(null);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      void handleMeetExchange();
                    }
                  }}
                  autoCapitalize="none"
                  autoComplete="off"
                  spellCheck={false}
                  placeholder="their_username"
                />
                {canUseSpeech && (
                  <button
                    type="button"
                    className="meet-speech"
                    onClick={startSpeech}
                    disabled={listening}
                  >
                    {listening ? "Listening" : "Speak"}
                  </button>
                )}
              </div>
              {meetLookupUsername.length >= 3 && meetLookup === undefined && (
                <p className="meet-muted" role="status">
                  checking @{meetLookupUsername}
                </p>
              )}
              {meetLookupUsername.length >= 3 &&
                meetLookup === null &&
                meetError === null && (
                  <p className="meet-error">No Euno profile found for that username.</p>
                )}
              {meetLookup !== undefined &&
                meetLookup !== null &&
                meetLookup.username === profile.username && (
                  <p className="meet-error">Enter the other person's username.</p>
                )}
              {meetLookup !== undefined &&
                meetLookup !== null &&
                meetLookup.username !== profile.username && (
                  <p className="meet-found">Found @{meetLookup.username}.</p>
                )}
              <button
                type="button"
                className="atlas-add meet-primary"
                disabled={
                  exchanging ||
                  meetLookup === undefined ||
                  meetLookup === null ||
                  meetLookup.username === profile.username
                }
                onClick={() => void handleMeetExchange()}
              >
                {exchanging && <span className="spinner" aria-hidden="true" />}
                Confirm exchange
              </button>
              {lastMeet !== null && (
                <button
                  type="button"
                  className="meet-open"
                  onClick={() =>
                    onOpen({
                      _id: lastMeet.personId,
                      name: `@${lastMeet.peerUsername}`,
                      _creationTime: Date.now(),
                    })
                  }
                >
                  Open @{lastMeet.peerUsername}
                </button>
              )}
            </div>
          )}

          {meetStatus !== null && <p className="meet-status">{meetStatus}</p>}
          {meetError !== null && <p className="meet-error">{meetError}</p>}
        </section>
      )}

      {/* Clusters render in recency order so tab order = recency (decision 3),
          even though each button is absolutely positioned. */}
      {fieldLoaded && !isEmpty && (
        <div className="atlas-field">
          {field.map((person, i) => {
            const cluster = clusters[i];
            const pos = positions[i];
            const dim = !isLit(person._id);
            const memory = isMemory(person._id);
            return (
              <button
                type="button"
                key={person._id}
                className={`atlas-cluster${dim ? " is-dim" : ""}${
                  memory ? " is-memory" : ""
                }`}
                style={{
                  left: `${pos.x - boxW / 2}px`,
                  top: `${pos.y - boxH / 2}px`,
                  width: `${boxW}px`,
                }}
                onClick={() => onOpen(person)}
              >
                <svg
                  className="atlas-cluster-sky"
                  viewBox={`0 0 ${cluster.width} ${cluster.height}`}
                  width={boxW}
                  height={boxH}
                  aria-hidden="true"
                >
                  {cluster.edges.map(([a, b], e) => (
                    <line
                      key={e}
                      x1={cluster.stars[a].x.toFixed(1)}
                      y1={cluster.stars[a].y.toFixed(1)}
                      x2={cluster.stars[b].x.toFixed(1)}
                      y2={cluster.stars[b].y.toFixed(1)}
                      stroke="rgba(255,255,255,0.16)"
                      strokeWidth="0.8"
                    />
                  ))}
                  {cluster.stars.map((star, s) => (
                    <circle
                      key={s}
                      cx={star.x.toFixed(1)}
                      cy={star.y.toFixed(1)}
                      r={star.r.toFixed(2)}
                      fill={`hsla(${star.hue}, 60%, 88%, 1)`}
                    />
                  ))}
                </svg>
                <span
                  className="atlas-cluster-name"
                  style={
                    person._id === morphId
                      ? { viewTransitionName: "person-name" }
                      : undefined
                  }
                >
                  {person.name}
                </span>
                <span className="atlas-cluster-when">
                  {formatMonthYear(person._creationTime)}
                </span>
                {memory && <span className="atlas-cluster-tag">memory</span>}
              </button>
            );
          })}
        </div>
      )}

      {/* First run: the sky is empty. Its own capture button lives inside. */}
      {isEmpty && (
        <div className="atlas-empty" role="status">
          <span className="sky-label">your sky is waiting</span>
          <h2 className="atlas-empty-title">No one here yet</h2>
          <p className="atlas-empty-body">
            Meet someone worth remembering, then capture them.
          </p>
          <button type="button" className="sky-cta" onClick={onOpenCapture}>
            Capture someone new
          </button>
        </div>
      )}

      {/* Loading: only the dust shows; after a beat, a quiet status label. */}
      {!fieldLoaded && showLoading && (
        <div className="atlas-loading" role="status">
          <span className="sky-label">reading your sky</span>
        </div>
      )}

      {/* The recent sky is capped; hint that the rest lives behind search. */}
      {atCap && !isEmpty && (
        <p className="atlas-hint sky-label">search to find everyone else</p>
      )}

      {fieldLoaded && <LoveAlarmPanel />}

      {/* Capture floats bottom-center whenever the sky already holds someone. */}
      {fieldLoaded && !isEmpty && (
        <div className="atlas-capture">
          <button type="button" className="sky-cta" onClick={onOpenCapture}>
            Capture someone new
          </button>
        </div>
      )}
    </form>
  );
}
