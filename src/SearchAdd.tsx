import { useQuery, useMutation } from "convex/react";
import { useRef, useState, type FormEvent } from "react";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";
import type { PersonSnapshot } from "./lib";

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
  morphId,
}: {
  query: string;
  onQueryChange: (query: string) => void;
  onOpen: (person: PersonSnapshot) => void;
  morphId: Id<"people"> | null;
}) {
  const results = useQuery(api.people.searchPeople, { query });
  const addPerson = useMutation(api.people.addPerson);
  const [adding, setAdding] = useState(false);
  const inputRef = useRef<HTMLInputElement | null>(null);

  const trimmed = query.trim();
  const loaded = results !== undefined;
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

      {showRecentLabel && <p className="list-label">Recent</p>}

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
