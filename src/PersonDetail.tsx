import { useQuery, useMutation } from "convex/react";
import { useEffect, useRef, useState } from "react";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";
import { formatMonthYear, normalizeUrl, type PersonSnapshot } from "./lib";
import { PersonSky } from "./PersonSky";

function ArrowUpRight() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M7 17 17 7M9 7h8v8"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function PersonDetail({
  id,
  initial,
  onSaved,
}: {
  id: Id<"people">;
  initial: PersonSnapshot | null;
  onSaved: () => void;
}) {
  const live = useQuery(api.people.getPerson, { id });
  const sharedNote = useQuery(api.sharedNotes.getForPerson, { personId: id });
  const updatePerson = useMutation(api.people.updatePerson);
  const updateSharedNote = useMutation(api.sharedNotes.updateForPerson);
  const deletePerson = useMutation(api.people.deletePerson);
  const [link, setLink] = useState(initial?.link ?? "");
  const [context, setContext] = useState(initial?.context ?? "");
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [sharedContext, setSharedContext] = useState("");
  const [sharedDirty, setSharedDirty] = useState(false);
  const [savingSharedNote, setSavingSharedNote] = useState(false);
  const [sharedSaveError, setSharedSaveError] = useState<string | null>(null);
  const [sharedSaved, setSharedSaved] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  // Catch focus when the confirm row swaps in so a keyboard user is never
  // dropped onto the body. Cancel (not Remove) so the safe choice is default
  // for an action that cannot be undone.
  const cancelDeleteRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (confirmingDelete) cancelDeleteRef.current?.focus();
  }, [confirmingDelete]);

  // The row snapshot renders instantly; once the authoritative doc arrives,
  // sync the form unless the user has already started typing.
  useEffect(() => {
    if (live !== undefined && live !== null && !dirty) {
      setLink(live.link ?? "");
      setContext(live.context ?? "");
    }
  }, [live, dirty]);

  useEffect(() => {
    if (sharedNote !== undefined && sharedNote !== null && !sharedDirty) {
      setSharedContext(sharedNote.content ?? "");
    }
  }, [sharedNote, sharedDirty]);

  // Live doc wins once loaded (null means not found / not owned).
  const person = live !== undefined ? live : initial;

  if (person === null) {
    return (
      <div className="empty-state" role="status">
        <h2 className="empty-title">That person is not available</h2>
        <p className="empty-body">They may have been removed.</p>
      </div>
    );
  }

  if (person === undefined) {
    // Deep load with no snapshot in hand; rare.
    return (
      <div className="person-detail" aria-busy="true">
        <div className="skeleton-line skeleton-title" />
        <div className="skeleton-line" style={{ width: "30%" }} />
        <div className="skeleton-line skeleton-block" />
      </div>
    );
  }

  const openable = normalizeUrl(link);

  async function handleSave() {
    if (saving) return;
    setSaving(true);
    setSaveError(null);
    try {
      await updatePerson({
        id,
        link: link.trim() === "" ? undefined : link.trim(),
        context: context.trim() === "" ? undefined : context.trim(),
      });
      onSaved();
    } catch {
      setSaveError("Could not save. Please try again.");
      setSaving(false);
    }
  }

  async function handleSaveSharedNote() {
    if (savingSharedNote || sharedNote === undefined || sharedNote === null) {
      return;
    }
    setSavingSharedNote(true);
    setSharedSaveError(null);
    try {
      await updateSharedNote({
        personId: id,
        content: sharedContext.trim() === "" ? undefined : sharedContext.trim(),
      });
      setSharedDirty(false);
      setSharedSaved(true);
    } catch {
      setSharedSaveError("Could not save shared notes. Please try again.");
    } finally {
      setSavingSharedNote(false);
    }
  }

  async function handleDelete() {
    if (deleting) return;
    setDeleting(true);
    setDeleteError(null);
    try {
      await deletePerson({ personId: id });
      // The search screen's live query drops the row on its own; onSaved just
      // takes us back there. No state reset needed -- this unmounts.
      onSaved();
    } catch {
      setDeleteError("Could not remove. Please try again.");
      setDeleting(false);
    }
  }

  return (
    <div className="person-detail">
      <div className="person-sky-band">
        <div className="sky-space" aria-hidden="true" />
        {/* Seeded by the document id, which is the route: it is identical on
            the snapshot and the live doc, so the starfield does not re-mint
            when the doc arrives, and it is the same seed the atlas cluster
            uses, so this is visibly the star that was tapped. Renaming
            somebody leaves their sky alone. */}
        <PersonSky seed={id} />
        <div className="sky-vignette" aria-hidden="true" />
        <div className="person-sky-content">
          <h1 className="person-name">{person.name}</h1>
        </div>
      </div>
      <p className="person-meta">Added {formatMonthYear(person._creationTime)}</p>

      {/* Reserved slot: the source screenshot thumbnail belongs here, in the
          quiet register above the link. Deferred this round -- getPerson does
          not project an image URL yet (it returns screenshotId only), so there
          is nothing to render client-side. Once getPerson resolves
          ctx.storage.getUrl(screenshotId) into an imageUrl, render a small
          .person-thumb here; the layout already leaves room for it. */}

      <div className="detail-field">
        <div className="field-row">
          <label htmlFor="person-link">Link</label>
          {openable !== null && (
            <a
              className="open-link"
              href={openable}
              target="_blank"
              rel="noopener noreferrer"
            >
              Open
              <ArrowUpRight />
            </a>
          )}
        </div>
        <input
          id="person-link"
          className="field"
          type="text"
          inputMode="url"
          autoCapitalize="none"
          autoComplete="off"
          spellCheck={false}
          placeholder="https://..."
          value={link}
          onChange={(e) => {
            setLink(e.target.value);
            setDirty(true);
          }}
        />
      </div>
      <div className="detail-field">
        <label htmlFor="person-context">Private context</label>
        <textarea
          id="person-context"
          className="field"
          placeholder="How you met, what they are working on, anything you want to remember"
          value={context}
          onChange={(e) => {
            setContext(e.target.value);
            setDirty(true);
          }}
        />
      </div>
      {saveError !== null && (
        <p className="form-error" role="alert">
          {saveError}
        </p>
      )}
      <div className="actions">
        <button
          className="btn-primary"
          type="button"
          disabled={saving}
          onClick={() => void handleSave()}
        >
          {saving ? (
            <>
              <span className="spinner" aria-hidden="true" />
              Saving
            </>
          ) : (
            "Save"
          )}
        </button>
      </div>

      <section
        className="shared-note-card"
        aria-busy={sharedNote === undefined ? "true" : "false"}
      >
        <div className="shared-note-heading">
          <h2 className="shared-note-title">Shared notes</h2>
          <p className="shared-note-copy">
            A quiet space for mutual memory. Your private context above stays
            yours.
          </p>
        </div>
        {sharedNote === undefined ? (
          <div className="skeleton-line skeleton-block" />
        ) : sharedNote === null ? (
          <p className="shared-note-copy">
            Available after you and {person.name} both connect in Haven.
          </p>
        ) : (
          <>
            <textarea
              id="person-shared-note"
              className="field shared-note-field"
              aria-label="Shared notes"
              placeholder="What you both want to remember about this connection"
              value={sharedContext}
              onChange={(e) => {
                setSharedContext(e.target.value);
                setSharedDirty(true);
                setSharedSaved(false);
              }}
            />
            <div className="shared-note-actions">
              <p className="shared-note-status" role={sharedSaved ? "status" : undefined}>
                {sharedSaved
                  ? "Shared notes saved"
                  : sharedNote.updatedAt === undefined
                    ? "Only visible to this connected pair"
                    : sharedNote.updatedByMe
                      ? "Last updated by you"
                      : `Last updated by ${person.name}`}
              </p>
              <button
                className="btn-ghost"
                type="button"
                disabled={savingSharedNote || !sharedDirty}
                onClick={() => void handleSaveSharedNote()}
              >
                {savingSharedNote ? "Saving" : "Save shared notes"}
              </button>
            </div>
            {sharedSaveError !== null && (
              <p className="form-error" role="alert">
                {sharedSaveError}
              </p>
            )}
          </>
        )}
      </section>

      <div className="person-danger">
        {confirmingDelete ? (
          <div className="person-remove-confirm">
            <p className="person-remove-prompt" role="alert">
              Remove {person.name}? This cannot be undone.
            </p>
            <div className="person-remove-actions">
              <button
                ref={cancelDeleteRef}
                className="btn-ghost"
                type="button"
                disabled={deleting}
                onClick={() => setConfirmingDelete(false)}
              >
                Cancel
              </button>
              <button
                className="btn-danger"
                type="button"
                disabled={deleting}
                onClick={() => void handleDelete()}
              >
                {deleting ? (
                  <>
                    <span className="spinner" aria-hidden="true" />
                    Removing
                  </>
                ) : (
                  "Remove"
                )}
              </button>
            </div>
          </div>
        ) : (
          <button
            className="person-remove"
            type="button"
            onClick={() => setConfirmingDelete(true)}
          >
            Remove from your network
          </button>
        )}
        {deleteError !== null && (
          <p className="form-error" role="alert">
            {deleteError}
          </p>
        )}
      </div>
    </div>
  );
}
