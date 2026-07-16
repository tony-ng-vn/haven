import { useQuery, useMutation } from "convex/react";
import { useEffect, useState } from "react";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";
import { formatMonthYear, normalizeUrl, type PersonSnapshot } from "./lib";

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
  const updatePerson = useMutation(api.people.updatePerson);
  const [link, setLink] = useState(initial?.link ?? "");
  const [context, setContext] = useState(initial?.context ?? "");
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // The row snapshot renders instantly; once the authoritative doc arrives,
  // sync the form unless the user has already started typing.
  useEffect(() => {
    if (live !== undefined && live !== null && !dirty) {
      setLink(live.link ?? "");
      setContext(live.context ?? "");
    }
  }, [live, dirty]);

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

  return (
    <div className="person-detail">
      <h1 className="person-name">{person.name}</h1>
      <p className="person-meta">Added {formatMonthYear(person._creationTime)}</p>
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
        <label htmlFor="person-context">Context</label>
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
    </div>
  );
}
