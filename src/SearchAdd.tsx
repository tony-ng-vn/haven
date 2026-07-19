import { useQuery, useMutation, useAction } from "convex/react";
import { useEffect, useRef, useState, type FormEvent } from "react";
import type { FunctionReturnType } from "convex/server";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";
import type { PersonSnapshot } from "./lib";

type SemanticResults = FunctionReturnType<typeof api.people.semanticSearch>;

function ImagesIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect
        x="3.5"
        y="5.5"
        width="17"
        height="13"
        rx="2.5"
        stroke="currentColor"
        strokeWidth="2"
      />
      <circle cx="9" cy="10.2" r="1.6" fill="currentColor" />
      <path
        d="m6 17 4.2-4.2a1.5 1.5 0 0 1 2.1 0L18 18.5"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  );
}

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
  const results = useQuery(api.people.searchPeople, { query });
  const addPerson = useMutation(api.people.addPerson);
  const semanticSearch = useAction(api.people.semanticSearch);
  const [adding, setAdding] = useState(false);
  const [semantic, setSemantic] = useState<SemanticResults>([]);
  const inputRef = useRef<HTMLInputElement | null>(null);

  const trimmed = query.trim();

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
  const loaded = results !== undefined;

  // Only the home list (no query typed yet) gets a skeleton, and only once
  // loading has run long enough to be worth acknowledging -- fast answers
  // should still render with no flash at all.
  const [showHomeSkeleton, setShowHomeSkeleton] = useState(false);
  useEffect(() => {
    if (loaded) {
      setShowHomeSkeleton(false);
      return;
    }
    const timer = setTimeout(() => setShowHomeSkeleton(true), 300);
    return () => clearTimeout(timer);
  }, [loaded]);

  const list = results ?? [];
  const hasExact = list.some(
    (p) => p.name.toLowerCase() === trimmed.toLowerCase(),
  );
  // Nothing renders until the query answers, so states never flash.
  const showAdd = loaded && trimmed !== "" && !hasExact;
  const showRecentLabel = loaded && trimmed === "" && list.length > 0;
  const showFirstRun = loaded && trimmed === "" && list.length === 0;

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

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (showAdd) void handleAdd();
  }

  return (
    <form className="search-add" onSubmit={handleSubmit}>
      <div className="search-wrap">
        <SearchIcon />
        <input
          ref={inputRef}
          className="field search-input"
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
            className="search-clear"
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

      {trimmed === "" && (
        <button
          type="button"
          className="btn-ghost capture-entry"
          onClick={onOpenCapture}
        >
          <ImagesIcon />
          Add from screenshots
        </button>
      )}

      {showRecentLabel && <p className="list-label">Recent</p>}

      {!loaded && trimmed === "" && showHomeSkeleton && (
        <ul className="results" aria-hidden="true">
          {[0, 1, 2].map((i) => (
            <li key={i}>
              <div className="skeleton-line result-row-skeleton" />
            </li>
          ))}
        </ul>
      )}

      <ul className="results">
        {list.map((p) => (
          <li key={p._id}>
            <button
              type="button"
              className="result-row"
              onClick={() => onOpen(p)}
            >
              <span
                className="row-name"
                style={
                  p._id === morphId
                    ? { viewTransitionName: "person-name" }
                    : undefined
                }
              >
                {p.name}
              </span>
            </button>
          </li>
        ))}
      </ul>

      {trimmed !== "" &&
        (() => {
          const extra = semantic.filter(
            (match) => !list.some((p) => p._id === match._id),
          );
          if (extra.length === 0) return null;
          return (
            <>
              <p className="list-label">From your memory</p>
              <ul className="results">
                {extra.map((match) => (
                  <li key={match._id}>
                    <button
                      type="button"
                      className="result-row"
                      onClick={() =>
                        onOpen({
                          _id: match._id,
                          name: match.name,
                          link: match.link,
                          context: match.context,
                          _creationTime: match._creationTime,
                        })
                      }
                    >
                      <span
                        className="row-name"
                        style={
                          match._id === morphId
                            ? { viewTransitionName: "person-name" }
                            : undefined
                        }
                      >
                        {match.name}
                      </span>
                      {(match.context ?? match.headline) !== undefined && (
                        <span className="row-snippet">
                          {match.context ?? match.headline}
                        </span>
                      )}
                    </button>
                  </li>
                ))}
              </ul>
            </>
          );
        })()}

      {showFirstRun && (
        <div className="empty-state" role="status">
          <h2 className="empty-title">No one here yet</h2>
          <p className="empty-body">
            Type a name above to remember your first person.
          </p>
        </div>
      )}

      {showAdd && (
        <button type="submit" className="btn-primary add-button" disabled={adding}>
          {adding && <span className="spinner" aria-hidden="true" />}
          {`Add "${trimmed}"`}
        </button>
      )}
    </form>
  );
}
