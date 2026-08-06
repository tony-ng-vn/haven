import { useQuery, useMutation } from "convex/react";
import { useEffect, useRef, useState, type PointerEvent } from "react";
import type { FunctionReturnType } from "convex/server";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";
import {
  canSaveManualName,
  captureWasSaved,
  composeHeadline,
  composeName,
  decideSwipe,
  deriveProfileUrl,
  normalizeUrl,
  rubberband,
  triageCountLabel,
} from "./lib";
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

// Uploads one screenshot in isolation and reports whether it landed, so a
// bad file in a batch never voids the ones around it.
export async function uploadScreenshot(
  file: File,
  deps: {
    generateUploadUrl: () => Promise<string>;
    createCapture: (args: { screenshotId: Id<"_storage"> }) => Promise<unknown>;
  },
): Promise<boolean> {
  try {
    const uploadUrl = await deps.generateUploadUrl();
    const response = await fetch(uploadUrl, {
      method: "POST",
      headers: { "Content-Type": file.type },
      body: file,
    });
    if (!response.ok) return false;
    const { storageId } = (await response.json()) as {
      storageId: Id<"_storage">;
    };
    await deps.createCapture({ screenshotId: storageId });
    return true;
  } catch {
    return false;
  }
}

export function CaptureTriage() {
  const captures = useQuery(api.captures.listCaptures, {});
  const generateUploadUrl = useMutation(api.captures.generateUploadUrl);
  const createCapture = useMutation(api.captures.createCapture);
  const acceptCapture = useMutation(api.captures.acceptCapture);
  const acceptManualCapture = useMutation(api.captures.acceptManualCapture);
  const discardCapture = useMutation(api.captures.discardCapture);
  const retryExtract = useMutation(api.captures.retryExtract);

  const [uploading, setUploading] = useState(0);
  const [uploadFailures, setUploadFailures] = useState(0);
  const [savedCount, setSavedCount] = useState(0);
  const [mode, setMode] = useState<"card" | "context">("card");
  const [contextDraft, setContextDraft] = useState("");
  const [linkDraft, setLinkDraft] = useState("");
  // Manual "name this star" fields, used when a capture could not be read.
  const [firstDraft, setFirstDraft] = useState("");
  const [lastDraft, setLastDraft] = useState("");
  const [workDraft, setWorkDraft] = useState("");
  const [schoolDraft, setSchoolDraft] = useState("");
  const [drag, setDrag] = useState({ x: 0, y: 0, dragging: false });
  const [leaving, setLeaving] = useState<Capture | null>(null);
  // Guards save()/skip() while the top card's mutation is in flight, so a
  // second tap (or a slow network) can't fire it twice.
  const [busy, setBusy] = useState(false);
  // A brief inline message when a save/skip mutation actually fails.
  const [actionError, setActionError] = useState<string | null>(null);
  // The ignition reveal plays only when we witness this card finish
  // reading (pending -> ready on the visible top card). Cards that were
  // already ready surface without ceremony, so batch triage stays fast.
  const [revealId, setRevealId] = useState<Capture["_id"] | null>(null);
  const prevTopRef = useRef<{ id: Capture["_id"]; status: string } | null>(null);

  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const firstNameRef = useRef<HTMLInputElement | null>(null);
  const cardRef = useRef<HTMLDivElement | null>(null);
  // A manual card's name lives in the draft fields, which reset the instant
  // the next card arrives. Freeze the saved name here so the card keeps it
  // while it flies off, instead of blanking to "unnamed star" mid-exit.
  const leavingNameRef = useRef("");
  const pointer = useRef({ startX: 0, startY: 0, baseX: 0 });
  const history = useRef<Array<{ t: number; x: number }>>([]);
  // Tracks the pending "clear leaving" timeout so a second fast save can
  // cancel it instead of letting it cut the new card's exit short.
  const leavingTimeoutRef = useRef<number | null>(null);
  const actionErrorTimeoutRef = useRef<number | null>(null);
  const [reduceMotion] = useState(() =>
    window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );

  useEffect(() => {
    return () => {
      if (leavingTimeoutRef.current !== null) {
        window.clearTimeout(leavingTimeoutRef.current);
      }
      if (actionErrorTimeoutRef.current !== null) {
        window.clearTimeout(actionErrorTimeoutRef.current);
      }
    };
  }, []);

  // Oldest first: triage in the order the screenshots were taken.
  const queue = [...(captures ?? [])].reverse();
  const top = queue[0];
  const under = queue[1];
  const topId = top?._id;

  // The human-supplied identity for a manual card, recomposed each render.
  const composedName = composeName(firstDraft, lastDraft);
  const composedHeadline = composeHeadline(workDraft, schoolDraft);
  const canSaveManual = canSaveManualName(composedName);

  // Fresh card, fresh slate.
  useEffect(() => {
    setMode("card");
    setContextDraft("");
    setLinkDraft("");
    setFirstDraft("");
    setLastDraft("");
    setWorkDraft("");
    setSchoolDraft("");
    setDrag({ x: 0, y: 0, dragging: false });
  }, [topId]);

  // Focus the first-name field whenever a manual card is the one to name, so
  // naming needs no reach for the input. The autoFocus attribute only fires
  // on first mount; consecutive failed cards reuse the node, and with the
  // dead OCR key every capture fails, so that is the common case.
  useEffect(() => {
    if (top?.status === "failed" && mode === "card") {
      firstNameRef.current?.focus();
    }
  }, [topId, top?.status, mode]);

  useEffect(() => {
    const prev = prevTopRef.current;
    if (top === undefined) {
      prevTopRef.current = null;
      return;
    }
    if (
      prev !== null &&
      prev.id === top._id &&
      prev.status === "pending" &&
      top.status === "ready"
    ) {
      setRevealId(top._id);
    }
    prevTopRef.current = { id: top._id, status: top.status };
  }, [top]);

  async function handleFiles(files: FileList | null) {
    if (files === null || files.length === 0) return;
    const chosen = Array.from(files);
    // A fresh batch retires the previous batch's failure banner, and the
    // accumulate below keeps overlapping batches from clobbering each
    // other's counts.
    setUploadFailures(0);
    setUploading((n) => n + chosen.length);
    const outcomes = await Promise.all(
      chosen.map(async (file) => {
        const ok = await uploadScreenshot(file, { generateUploadUrl, createCapture });
        setUploading((n) => n - 1);
        return ok;
      }),
    );
    const failed = outcomes.filter((ok) => !ok).length;
    if (failed > 0) setUploadFailures((n) => n + failed);
  }

  function resolvedLink(capture: Capture): string | undefined {
    const extracted = capture.extracted;
    if (extracted === undefined) return undefined;
    const derived = deriveProfileUrl(extracted.platform, extracted.handle);
    if (derived !== null) return derived;
    return normalizeUrl(linkDraft) ?? undefined;
  }

  function clearLeavingTimeout() {
    if (leavingTimeoutRef.current !== null) {
      window.clearTimeout(leavingTimeoutRef.current);
      leavingTimeoutRef.current = null;
    }
  }

  // Shows a message under the actions briefly, then clears itself so a
  // stale failure doesn't linger once the user moves on.
  function flashActionError(message: string) {
    setActionError(message);
    if (actionErrorTimeoutRef.current !== null) {
      window.clearTimeout(actionErrorTimeoutRef.current);
    }
    actionErrorTimeoutRef.current = window.setTimeout(() => {
      setActionError(null);
      actionErrorTimeoutRef.current = null;
    }, 2600);
  }

  // A failed capture is named by hand (acceptManualCapture); a ready one
  // carries its extracted profile (acceptCapture). One save path, two
  // mutations -- picked here so the leaving/busy machinery stays shared.
  // Both share captureAcceptReturns' shape, so either call resolves to the
  // same outcome type -- callers branch on .status without knowing which
  // mutation actually ran.
  function acceptForCard(
    capture: Capture,
    context?: string,
  ): Promise<FunctionReturnType<typeof api.captures.acceptCapture>> {
    if (capture.status === "failed") {
      return acceptManualCapture({
        captureId: capture._id,
        name: composedName,
        headline: composedHeadline,
        context,
      });
    }
    return acceptCapture({
      captureId: capture._id,
      link: resolvedLink(capture),
      context,
    });
  }

  function save(capture: Capture, context?: string) {
    if (busy) return;
    // A manual card with no name yet cannot leave the deck: rubber-band it
    // back and say so, rather than firing a mutation that would be rejected.
    if (capture.status === "failed" && !canSaveManual) {
      flashActionError("Name them first");
      setDrag({ x: 0, y: 0, dragging: false });
      return;
    }
    setBusy(true);
    setActionError(null);
    // Freeze the manual name for the exit; ready cards render from their own
    // extracted data, so this is a no-op string for them.
    leavingNameRef.current =
      capture.status === "failed" ? composedName : "";

    if (reduceMotion) {
      acceptForCard(capture, context)
        .then((result) => {
          if (!captureWasSaved(result)) {
            flashActionError("Already saved to someone else -- nothing changed");
            return;
          }
          setSavedCount((n) => n + 1);
        })
        .catch(() => flashActionError("Could not save -- try again"))
        .finally(() => setBusy(false));
      return;
    }

    // The card flies off while the mutation lands; the next card is
    // already underneath. Cancel any still-pending exit from a previous
    // fast save so it can't clear *this* card's leaving state early.
    clearLeavingTimeout();
    setLeaving(capture);
    acceptForCard(capture, context)
      .then((result) => {
        if (!captureWasSaved(result)) {
          // A conflict writes nothing server-side -- the capture is still
          // in triage, so bring the card back rather than let it finish
          // flying off as though it landed. Same rollback as a failed
          // mutation below, minus the retry framing: this is not an error
          // the user can fix by tapping save again.
          clearLeavingTimeout();
          setLeaving(null);
          setDrag({ x: 0, y: 0, dragging: false });
          flashActionError("Already saved to someone else -- nothing changed");
          return;
        }
        setSavedCount((n) => n + 1);
      })
      .catch(() => {
        // The mutation didn't land: bring the card back instead of
        // leaving it stuck off-screen. A fling-save parks displacement in
        // drag (not just leaving), and the [topId] reset never fires when
        // the failed mutation rolls back, so clear it here explicitly.
        clearLeavingTimeout();
        setLeaving(null);
        setDrag({ x: 0, y: 0, dragging: false });
        flashActionError("Could not save -- try again");
      })
      .finally(() => setBusy(false));
    leavingTimeoutRef.current = window.setTimeout(() => {
      setLeaving(null);
      leavingTimeoutRef.current = null;
    }, 340);
  }

  function saveWithContext(capture: Capture) {
    const trimmed = contextDraft.trim();
    save(capture, trimmed === "" ? undefined : trimmed);
  }

  function skip(capture: Capture) {
    if (busy) return;
    setBusy(true);
    setActionError(null);
    discardCapture({ captureId: capture._id })
      .catch(() => flashActionError("Could not skip -- try again"))
      .finally(() => setBusy(false));
  }

  // One more try at reading the screenshot automatically. The capture drops
  // back to pending and shows the reading skeleton until it resolves again.
  function retry(capture: Capture) {
    if (busy) return;
    setBusy(true);
    setActionError(null);
    retryExtract({ captureId: capture._id })
      .catch(() => flashActionError("Could not retry -- try again"))
      .finally(() => setBusy(false));
  }

  // ------------------------------------------------------------- gestures

  const canDrag =
    !reduceMotion &&
    !busy &&
    top !== undefined &&
    (top.status === "ready" || top.status === "failed") &&
    mode === "card";

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

  function onPointerUp(_event: PointerEvent<HTMLDivElement>) {
    if (!drag.dragging || top === undefined) return;
    const decision = decideSwipe(drag.x, history.current);
    history.current = [];

    // An unnamed manual star can go neither way -- name it first.
    const blockedUnnamed = top.status === "failed" && !canSaveManual;

    if (decision === "save") {
      // Flung left: remember them now, context can wait.
      if (blockedUnnamed) {
        flashActionError("Name them first");
        setDrag({ x: 0, y: 0, dragging: false });
        return;
      }
      setDrag({ x: drag.x, y: drag.y, dragging: false });
      save(top);
      return;
    }
    if (decision === "context") {
      // Flung right: they matter; settle back and write the context.
      if (blockedUnnamed) {
        flashActionError("Name them first");
        setDrag({ x: 0, y: 0, dragging: false });
        return;
      }
      setDrag({ x: 0, y: 0, dragging: false });
      setMode("context");
      setContextDraft(top.extracted?.bio ?? "");
      return;
    }
    setDrag({ x: 0, y: 0, dragging: false });
  }

  // ------------------------------------------------------------ rendering

  if (captures === undefined) {
    return (
      <div className="triage">
        <div className="triage-toolbar">
          <button type="button" className="btn-ghost" disabled>
            Add more
          </button>
        </div>
        <div className="triage-stack">
          <div className="triage-card" aria-busy="true">
            <div className="triage-body">
              <div className="skeleton-line skeleton-block" />
              <div className="skeleton-line skeleton-title" />
              <div className="skeleton-line" style={{ width: "55%" }} />
            </div>
          </div>
        </div>
      </div>
    );
  }

  // The rendered card is whichever one is leaving; once leaving !== null it
  // stays pinned there regardless of how fast the query updates `top`
  // underneath, so the exit animation always plays to completion.
  const isLeaving = leaving !== null;
  const activeTop = leaving ?? top;
  // The manual card's name comes from the live drafts, except while leaving,
  // when the frozen name keeps it from blanking as the next card resets them.
  const manualName = isLeaving ? leavingNameRef.current : composedName;
  const rotation = Math.max(-8, Math.min(8, drag.x * 0.04));
  const cardStyle = isLeaving
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

      {uploadFailures > 0 && (
        <p className="form-error" role="alert">
          {uploadFailures === 1
            ? "1 screenshot failed to upload -- try again"
            : `${uploadFailures} screenshots failed to upload -- try again`}
        </p>
      )}

      {showIntro ? (
        <div className="empty-state" role="status">
          <h2 className="empty-title">
            {savedCount === 0 ? "Add people from screenshots" : "All caught up"}
          </h2>
          <p className="empty-body">
            {savedCount === 0
              ? "Screenshot profiles as you meet people. Upload them here and Haven reads out who they are."
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
                : triageCountLabel(queue.length)}
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
                  activeTop.status === "ready" || activeTop.status === "failed"
                    ? " triage-card-sky"
                    : ""
                }${activeTop._id === revealId ? " sky-reveal" : ""}${
                  isLeaving ? " triage-card-exit" : ""
                }`}
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
                  <div className="triage-body triage-sky-body">
                    <div className="sky-space" aria-hidden="true" />
                    {/* A capture is not a person yet, so there is no identity
                        to seed from -- this is the typed name, or the capture
                        itself before anything has been typed. */}
                    <PersonSky seed={manualName === "" ? activeTop._id : manualName} />
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
                    <div className="sky-content manual-content">
                      {activeTop.imageUrl !== null && (
                        <img
                          className="triage-thumb manual-thumb"
                          src={activeTop.imageUrl}
                          alt="Your screenshot of this person"
                        />
                      )}
                      <div className="manual-lower">
                        {manualName === "" ? (
                          <p className="triage-meta manual-caption">
                            unnamed star
                          </p>
                        ) : (
                          <h2 className="triage-name manual-name">
                            {manualName}
                          </h2>
                        )}
                        {mode === "card" || isLeaving ? (
                          <>
                            <div className="manual-fields">
                              <input
                                ref={firstNameRef}
                                className="field manual-field"
                                type="text"
                                placeholder="First name"
                                value={firstDraft}
                                onChange={(e) => setFirstDraft(e.target.value)}
                                onPointerDown={(e) => e.stopPropagation()}
                              />
                              <input
                                className="field manual-field"
                                type="text"
                                placeholder="Last name"
                                value={lastDraft}
                                onChange={(e) => setLastDraft(e.target.value)}
                                onPointerDown={(e) => e.stopPropagation()}
                              />
                              <input
                                className="field manual-field"
                                type="text"
                                placeholder="Where they work (optional)"
                                value={workDraft}
                                onChange={(e) => setWorkDraft(e.target.value)}
                                onPointerDown={(e) => e.stopPropagation()}
                              />
                              <input
                                className="field manual-field"
                                type="text"
                                placeholder="School (optional)"
                                value={schoolDraft}
                                onChange={(e) => setSchoolDraft(e.target.value)}
                                onPointerDown={(e) => e.stopPropagation()}
                              />
                            </div>
                            <div className="manual-fail">
                              <p className="manual-fail-line">
                                Could not read this screenshot automatically
                              </p>
                              <button
                                type="button"
                                className="btn-ghost sky-ghost manual-retry"
                                disabled={busy}
                                onClick={() => retry(activeTop)}
                                onPointerDown={(e) => e.stopPropagation()}
                              >
                                Retry reading
                              </button>
                            </div>
                          </>
                        ) : (
                          <>
                            <textarea
                              className="field triage-context"
                              placeholder="How you met, what they are working on, anything you want to remember"
                              value={contextDraft}
                              autoFocus
                              onChange={(e) => setContextDraft(e.target.value)}
                              onPointerDown={(e) => e.stopPropagation()}
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
                                disabled={busy}
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
                  </div>
                )}

                {activeTop.status === "ready" &&
                  activeTop.extracted !== undefined && (
                    <div className="triage-body triage-sky-body">
                      <div className="sky-space" aria-hidden="true" />
                      {/* Same here: nobody has been saved, so the seed is the
                          extracted pair rather than an identity. It keeps this
                          card's sky exactly what it was before seeds were
                          unified. */}
                      <PersonSky
                        seed={activeTop.extracted.name + (activeTop.extracted.handle ?? "")}
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
                                disabled={busy}
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
                disabled={busy}
                onClick={() => skip(top)}
              >
                {top.status === "failed" ? "Discard" : "Skip"}
              </button>
              {top.status === "ready" && (
                <>
                  <button
                    type="button"
                    className="btn-ghost"
                    disabled={busy}
                    onClick={() => save(top)}
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    className="btn-primary"
                    disabled={busy}
                    onClick={() => {
                      setMode("context");
                      setContextDraft(top.extracted?.bio ?? "");
                    }}
                  >
                    Save + context
                  </button>
                </>
              )}
              {top.status === "failed" && (
                <>
                  <button
                    type="button"
                    className="btn-ghost"
                    disabled={busy || !canSaveManual}
                    onClick={() => save(top)}
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    className="btn-primary"
                    disabled={busy || !canSaveManual}
                    onClick={() => {
                      setMode("context");
                      setContextDraft("");
                    }}
                  >
                    Add context
                  </button>
                </>
              )}
            </div>
          )}

          {actionError !== null && (
            <p className="form-error triage-action-error" role="alert">
              {actionError}
            </p>
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
