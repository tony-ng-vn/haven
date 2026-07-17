import { useQuery, useMutation } from "convex/react";
import { useEffect, useRef, useState, type PointerEvent } from "react";
import type { FunctionReturnType } from "convex/server";
import { api } from "../convex/_generated/api";
import { deriveProfileUrl, normalizeUrl } from "./lib";
import { PersonSky } from "./PersonSky";

type Capture = FunctionReturnType<typeof api.captures.listCaptures>[number];

const PLATFORM_LABELS: Record<string, string> = {
  linkedin: "LinkedIn",
  x: "X",
  instagram: "Instagram",
  tiktok: "TikTok",
  github: "GitHub",
  facebook: "Facebook",
  threads: "Threads",
  bluesky: "Bluesky",
  other: "Profile",
};

// Scroll-style momentum projection: where would the card coast to?
function project(velocity: number, decelerationRate = 0.998): number {
  return ((velocity / 1000) * decelerationRate) / (1 - decelerationRate);
}

// Progressive resistance past a boundary; real things slow before they stop.
function rubberband(overshoot: number, dimension = 320, constant = 0.55): number {
  return (
    (overshoot * dimension * constant) /
    (dimension + constant * Math.abs(overshoot))
  );
}

export function CaptureTriage() {
  const captures = useQuery(api.captures.listCaptures, {});
  const generateUploadUrl = useMutation(api.captures.generateUploadUrl);
  const createCapture = useMutation(api.captures.createCapture);
  const acceptCapture = useMutation(api.captures.acceptCapture);
  const discardCapture = useMutation(api.captures.discardCapture);

  const [uploading, setUploading] = useState(0);
  const [savedCount, setSavedCount] = useState(0);
  const [mode, setMode] = useState<"card" | "context">("card");
  const [contextDraft, setContextDraft] = useState("");
  const [linkDraft, setLinkDraft] = useState("");
  const [drag, setDrag] = useState({ x: 0, y: 0, dragging: false });
  const [leaving, setLeaving] = useState<Capture | null>(null);

  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const cardRef = useRef<HTMLDivElement | null>(null);
  const pointer = useRef({ startX: 0, startY: 0, baseX: 0 });
  const history = useRef<Array<{ t: number; x: number }>>([]);
  const [reduceMotion] = useState(() =>
    window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );

  // Oldest first: triage in the order the screenshots were taken.
  const queue = [...(captures ?? [])].reverse();
  const top = queue[0];
  const under = queue[1];
  const topId = top?._id;

  // Fresh card, fresh slate.
  useEffect(() => {
    setMode("card");
    setContextDraft("");
    setLinkDraft("");
    setDrag({ x: 0, y: 0, dragging: false });
  }, [topId]);

  async function handleFiles(files: FileList | null) {
    if (files === null || files.length === 0) return;
    const chosen = Array.from(files);
    setUploading((n) => n + chosen.length);
    await Promise.all(
      chosen.map(async (file) => {
        try {
          const uploadUrl = await generateUploadUrl();
          const response = await fetch(uploadUrl, {
            method: "POST",
            headers: { "Content-Type": file.type },
            body: file,
          });
          const { storageId } = (await response.json()) as {
            storageId: Parameters<typeof createCapture>[0]["screenshotId"];
          };
          await createCapture({ screenshotId: storageId });
        } finally {
          setUploading((n) => n - 1);
        }
      }),
    );
  }

  function resolvedLink(capture: Capture): string | undefined {
    const extracted = capture.extracted;
    if (extracted === undefined) return undefined;
    const derived = deriveProfileUrl(extracted.platform, extracted.handle);
    if (derived !== null) return derived;
    return normalizeUrl(linkDraft) ?? undefined;
  }

  function save(capture: Capture, context?: string) {
    if (reduceMotion) {
      void acceptCapture({
        captureId: capture._id,
        link: resolvedLink(capture),
        context,
      });
      setSavedCount((n) => n + 1);
      return;
    }
    // The card flies off while the mutation lands; the next card is
    // already underneath.
    setLeaving(capture);
    void acceptCapture({
      captureId: capture._id,
      link: resolvedLink(capture),
      context,
    });
    setSavedCount((n) => n + 1);
    window.setTimeout(() => setLeaving(null), 340);
  }

  function saveWithContext(capture: Capture) {
    const trimmed = contextDraft.trim();
    save(capture, trimmed === "" ? undefined : trimmed);
  }

  function skip(capture: Capture) {
    void discardCapture({ captureId: capture._id });
  }

  // ------------------------------------------------------------- gestures

  const canDrag =
    !reduceMotion && top !== undefined && top.status === "ready" && mode === "card";

  function onPointerDown(event: PointerEvent<HTMLDivElement>) {
    if (!canDrag || cardRef.current === null) return;
    cardRef.current.setPointerCapture(event.pointerId);
    // Grab from the card's live position so a mid-spring catch has no jump.
    const matrix = new DOMMatrixReadOnly(
      getComputedStyle(cardRef.current).transform,
    );
    pointer.current = {
      startX: event.clientX,
      startY: event.clientY,
      baseX: matrix.m41,
    };
    history.current = [{ t: event.timeStamp, x: matrix.m41 }];
    setDrag({ x: matrix.m41, y: 0, dragging: true });
  }

  function onPointerMove(event: PointerEvent<HTMLDivElement>) {
    if (!drag.dragging) return;
    const x = pointer.current.baseX + (event.clientX - pointer.current.startX);
    const y = rubberband(event.clientY - pointer.current.startY);
    history.current.push({ t: event.timeStamp, x });
    if (history.current.length > 6) history.current.shift();
    setDrag({ x, y, dragging: true });
  }

  function onPointerUp(event: PointerEvent<HTMLDivElement>) {
    if (!drag.dragging || top === undefined) return;
    const samples = history.current;
    const last = samples[samples.length - 1];
    const first =
      samples.find((s) => last.t - s.t <= 100) ?? samples[0];
    const velocity =
      last.t > first.t ? ((last.x - first.x) / (last.t - first.t)) * 1000 : 0;
    const projected = drag.x + project(velocity);
    history.current = [];
    void event;

    if (projected < -240) {
      // Flung left: remember them now, context can wait.
      setDrag({ x: drag.x, y: drag.y, dragging: false });
      save(top);
      return;
    }
    if (projected > 240) {
      // Flung right: they matter; settle back and write the context.
      setDrag({ x: 0, y: 0, dragging: false });
      setMode("context");
      setContextDraft(top.extracted?.bio ?? "");
      return;
    }
    setDrag({ x: 0, y: 0, dragging: false });
  }

  // ------------------------------------------------------------ rendering

  if (captures === undefined) {
    return null;
  }

  const isLeaving = leaving !== null && leaving._id === topId;
  const activeTop = leaving ?? top;
  const rotation = Math.max(-8, Math.min(8, drag.x * 0.04));
  const cardStyle = isLeaving || leaving !== null
    ? undefined
    : {
        transform: `translate(${drag.x}px, ${drag.y}px) rotate(${rotation}deg)`,
        transition: drag.dragging
          ? "none"
          : "transform 320ms cubic-bezier(0.23, 1, 0.32, 1)",
      };

  const showIntro = queue.length === 0 && leaving === null && uploading === 0;

  return (
    <div className="triage">
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        multiple
        hidden
        onChange={(e) => {
          void handleFiles(e.target.files);
          e.target.value = "";
        }}
      />

      {showIntro ? (
        <div className="empty-state" role="status">
          <h2 className="empty-title">
            {savedCount === 0 ? "Add people from screenshots" : "All caught up"}
          </h2>
          <p className="empty-body">
            {savedCount === 0
              ? "Screenshot profiles as you meet people. Upload them here and Euno reads out who they are."
              : savedCount === 1
                ? "1 person added to your people."
                : `${savedCount} people added to your people.`}
          </p>
          <button
            type="button"
            className="btn-primary triage-upload"
            onClick={() => fileInputRef.current?.click()}
          >
            Choose screenshots
          </button>
        </div>
      ) : (
        <>
          <div className="triage-toolbar">
            <button
              type="button"
              className="btn-ghost"
              onClick={() => fileInputRef.current?.click()}
            >
              Add more
            </button>
            <span className="triage-count">
              {uploading > 0
                ? `Uploading ${uploading}...`
                : queue.length === 1
                  ? "1 to review"
                  : `${queue.length} to review`}
            </span>
          </div>

          <div className="triage-stack">
            {under !== undefined && leaving === null && (
              <div className="triage-card triage-card-under" aria-hidden="true" />
            )}

            {activeTop !== undefined && (
              <div
                ref={cardRef}
                className={`triage-card${
                  activeTop.status === "ready" ? " triage-card-sky" : ""
                }${isLeaving ? " triage-card-exit" : ""}`}
                style={cardStyle}
                onPointerDown={onPointerDown}
                onPointerMove={onPointerMove}
                onPointerUp={onPointerUp}
                onPointerCancel={onPointerUp}
              >
                {activeTop.status === "pending" && (
                  <div className="triage-body" aria-busy="true">
                    <div className="skeleton-line skeleton-block" />
                    <div className="skeleton-line skeleton-title" />
                    <div className="skeleton-line" style={{ width: "55%" }} />
                    <p className="triage-reading">Reading screenshot</p>
                  </div>
                )}

                {activeTop.status === "failed" && (
                  <div className="triage-body">
                    {activeTop.imageUrl !== null && (
                      <img
                        className="triage-thumb"
                        src={activeTop.imageUrl}
                        alt="Uploaded screenshot"
                      />
                    )}
                    <p className="form-error">
                      {activeTop.error ?? "Could not read this screenshot"}
                    </p>
                  </div>
                )}

                {activeTop.status === "ready" &&
                  activeTop.extracted !== undefined && (
                    <div className="triage-body triage-sky-body">
                      <PersonSky
                        name={activeTop.extracted.name}
                        handle={activeTop.extracted.handle}
                      />
                      <div className="sky-vignette" aria-hidden="true" />
                      {(mode === "card" || isLeaving) && (
                        <>
                          <span
                            className="swipe-label swipe-label-left"
                            style={{
                              opacity: Math.min(1, Math.max(0, -drag.x) / 120),
                            }}
                          >
                            Save
                          </span>
                          <span
                            className="swipe-label swipe-label-right"
                            style={{
                              opacity: Math.min(1, Math.max(0, drag.x) / 120),
                            }}
                          >
                            Add context
                          </span>
                        </>
                      )}
                      <div className="sky-content">
                        <h2 className="triage-name">
                          {activeTop.extracted.name}
                        </h2>
                        <p className="triage-meta">
                          {PLATFORM_LABELS[activeTop.extracted.platform] ??
                            activeTop.extracted.platform}
                          {activeTop.extracted.handle !== undefined &&
                            ` ${activeTop.extracted.handle}`}
                        </p>
                        {mode === "card" || isLeaving ? (
                          <>
                            {(activeTop.extracted.headline ??
                              activeTop.extracted.bio) !== undefined && (
                              <p className="sky-bio">
                                {activeTop.extracted.headline ??
                                  activeTop.extracted.bio}
                              </p>
                            )}
                            {deriveProfileUrl(
                              activeTop.extracted.platform,
                              activeTop.extracted.handle,
                            ) !== null ? (
                              <span className="sky-link-pill">
                                {deriveProfileUrl(
                                  activeTop.extracted.platform,
                                  activeTop.extracted.handle,
                                )}
                              </span>
                            ) : (
                              <input
                                className="field triage-link-input"
                                type="text"
                                inputMode="url"
                                autoCapitalize="none"
                                spellCheck={false}
                                placeholder="Their profile link (optional)"
                                value={linkDraft}
                                onChange={(e) => setLinkDraft(e.target.value)}
                                onPointerDown={(e) => e.stopPropagation()}
                              />
                            )}
                          </>
                        ) : (
                          <>
                            <textarea
                              className="field triage-context"
                              placeholder="How you met, what they are working on, anything you want to remember"
                              value={contextDraft}
                              autoFocus
                              onChange={(e) => setContextDraft(e.target.value)}
                            />
                            <div className="actions">
                              <button
                                type="button"
                                className="btn-ghost sky-ghost"
                                onClick={() => setMode("card")}
                              >
                                Back
                              </button>
                              <button
                                type="button"
                                className="btn-primary"
                                onClick={() =>
                                  top !== undefined && saveWithContext(top)
                                }
                              >
                                Save
                              </button>
                            </div>
                          </>
                        )}
                      </div>
                    </div>
                  )}
              </div>
            )}
          </div>

          {top !== undefined && mode === "card" && (
            <div className="triage-actions">
              <button
                type="button"
                className="btn-ghost triage-skip"
                onClick={() => skip(top)}
              >
                Skip
              </button>
              {top.status === "ready" && (
                <>
                  <button
                    type="button"
                    className="btn-ghost"
                    onClick={() => save(top)}
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    className="btn-primary"
                    onClick={() => {
                      setMode("context");
                      setContextDraft(top.extracted?.bio ?? "");
                    }}
                  >
                    Save + context
                  </button>
                </>
              )}
            </div>
          )}

          {savedCount > 0 && (
            <p className="triage-saved" role="status">
              {savedCount === 1 ? "1 added" : `${savedCount} added`}
            </p>
          )}
        </>
      )}
    </div>
  );
}
