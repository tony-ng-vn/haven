import { useQuery, useMutation } from "convex/react";
import { useEffect, useRef, useState } from "react";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";
import { formatMonthYear, normalizeUrl, type PersonSnapshot } from "./lib";
import { PersonSky } from "./PersonSky";
import { isLinkedInHandleStale, reachLabel, reachUrl, samePlatform } from "./reach";

/// Whether a field somebody left blank counts as something to draw. It does
/// not: half the fields on most people are empty, and an empty one has to
/// disappear rather than render as a stray comma.
function said(value: string | undefined): value is string {
  return value !== undefined && value !== "";
}

/// The line under their name: what they do, then where they are.
///
/// The web mirror of PersonModel.detail. A blank part is dropped rather than
/// shown as a stray separator -- MapKit hands back an empty admin area for
/// countries that have no states, so a city can arrive with a hole in it.
function detailLine(person: {
  role?: string;
  company?: string;
  city?: { name: string; admin?: string; country?: string };
}): string | null {
  const work = [person.role, person.company].filter(said);
  const city = [
    person.city?.name,
    person.city?.admin,
    person.city?.country,
  ].filter(said);
  // An empty half joins to "" and is dropped. Unlike iOS, where a city whose
  // every part is blank survives compactMap as an empty string and leaves a
  // dangling "Engineer | ".
  const halves = [work.join(", "), city.join(", ")].filter(said);
  return halves.length > 0 ? halves.join(" | ") : null;
}

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
  // A Convex storage url is signed and can stop resolving. A person without a
  // photo is an ordinary person, so a url that fails leaves the page it was
  // decorating rather than a broken-image glyph.
  //
  // The url that failed, not a boolean: one flaky request would otherwise hide
  // the photo for the rest of the visit, and a photo replaced from a phone
  // would arrive on the live subscription and be suppressed by the old flag.
  const [failedPhotoUrl, setFailedPhotoUrl] = useState<string | null>(null);
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

  // Read off `person`, which is the snapshot until the live doc lands. A tap on
  // the atlas already carries these -- searchPeople returns whole projected
  // rows -- and taking them from the snapshot is what keeps the name morph
  // honest: everything below the name is in place when the transition captures
  // the band, so the settled name does not get shoved upward a beat later.
  const preferredPlatform = person.preferredPlatform;
  const saved = person.contactHandles ?? [];
  // The one they said to use first leads, because that is what choosing it
  // meant; the rest keep the order they were saved in. samePlatform rather
  // than ===, because the server stores the platform string verbatim: a row
  // can hold "Instagram" while preferredPlatform says "instagram".
  const handles = [
    ...saved.filter((handle) => samePlatform(handle.platform, preferredPlatform)),
    ...saved.filter((handle) => !samePlatform(handle.platform, preferredPlatform)),
  ];
  const photoUrl = person.photoUrl ?? null;
  const detail = detailLine(person);
  // Their headline, or their bio standing in for it, mirroring iOS. `??` and
  // not `||`: an empty headline is still the headline, and it draws nothing
  // rather than falling through to the bio.
  const about = person.headline ?? person.bio;
  const connection = person.connection ?? null;

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
          {photoUrl !== null && photoUrl !== failedPhotoUrl && (
            <img
              className="person-photo"
              src={photoUrl}
              alt=""
              // The name under it says who this is; announcing "photo" gives a
              // screen reader nothing it can use.
              aria-hidden="true"
              onError={() => setFailedPhotoUrl(photoUrl)}
            />
          )}
          <h1 className="person-name">{person.name}</h1>
          {detail !== null && <p className="person-detail-line">{detail}</p>}
          {connection !== null && (
            <p
              className={
                connection.state === "connected"
                  ? "person-connection person-connection-live"
                  : "person-connection"
              }
            >
              {connection.state === "connected"
                ? "Connected"
                : "No longer connected"}
            </p>
          )}
        </div>
      </div>
      <p className="person-meta">Added {formatMonthYear(person._creationTime)}</p>

      {said(about) && <p className="person-about">{about}</p>}

      {connection?.state === "ended" && (
        // Said once, plainly, above the fields it is about. A row that stopped
        // following a card and does not say so reads as a person who simply
        // never changes anything.
        <p className="person-frozen">
          This is the last thing their card said. It will not change again.
        </p>
      )}

      {/* Reserved slot: the source screenshot thumbnail belongs here, in the
          quiet register above the link. Deferred this round -- getPerson
          projects the person's own photo (drawn in the band above) but only a
          screenshotId for the capture they came from, so there is nothing to
          render client-side. Once getPerson resolves
          ctx.storage.getUrl(screenshotId) into an imageUrl, render a small
          .person-thumb here; the layout already leaves room for it. */}

      {/* What the handle you saved was for. A row Haven can address is a link;
          one it cannot is still the handle, because that is still how you
          reach them -- unlike the public card, which drops what it cannot open
          because a stranger cannot act on a string either way. Drawn only when
          there is something to reach: nobody needs an empty heading. */}
      {handles.length > 0 && (
        <section className="person-reach">
          <h2 className="person-reach-title">Ways to reach them</h2>
          <ul className="card-handles person-handles">
            {handles.map((handle) => {
              const href = reachUrl(handle.platform, handle.value, handle.platformId);
              // A number dials in place: a new tab for tel: opens an empty
              // window that never comes back. Only the open web gets its own.
              const external = href !== null && href.startsWith("https://");
              const row = (
                <>
                  <span className="card-handle-label">
                    {reachLabel(handle.platform)}
                  </span>
                  {samePlatform(handle.platform, preferredPlatform) && (
                    <span className="person-handle-mark">preferred</span>
                  )}
                  {/* After the mark, not before it: the mark belongs with the
                      platform it describes, and keeping it out of the value's
                      place is what lets every value line up in one column
                      instead of shifting on whichever row is preferred. */}
                  <span className="card-handle-value">{handle.value}</span>
                </>
              );
              return (
                <li key={`${handle.platform}:${handle.value}`}>
                  {href === null ? (
                    <span className="card-handle person-handle">{row}</span>
                  ) : (
                    <a
                      className="card-handle person-handle"
                      href={href}
                      target={external ? "_blank" : undefined}
                      rel={external ? "noopener noreferrer" : undefined}
                    >
                      {row}
                    </a>
                  )}
                  {/* LinkedIn frees a vanity slug back into its pool six
                      months after the account holding it moves on -- see
                      isLinkedInHandleStale. Outside the link itself, so it
                      never reads as part of what gets tapped. */}
                  {isLinkedInHandleStale(handle.platform, handle.addedAt) && (
                    <p className="person-handle-stale">
                      Saved a while ago -- still the right link?
                    </p>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
      )}

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
        <label htmlFor="person-context">What you remember</label>
        <textarea
          id="person-context"
          className="field"
          placeholder="How you met, what they are working on, anything you want to remember"
          value={context}
          onChange={(e) => {
            setContext(e.target.value);
            setDirty(true);
          }}
          // Described by the hint below, not merely followed by it: a screen
          // reader announcing only "What you remember, edit text" would leave
          // somebody writing the one paragraph the hint exists to prevent.
          aria-describedby="person-context-hint"
        />
        {/* Dated lines are what "who did I meet last month" reads, and one line
            per entry is what makes each one findable on its own -- so say that
            here rather than let one paragraph grow. */}
        <p className="person-note-hint" id="person-context-hint">
          One line per thing. Each is searchable on its own.
        </p>
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
            A quiet space for mutual memory. The note you keep above stays
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
