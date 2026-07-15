import { useQuery, useMutation } from "convex/react";
import { useState } from "react";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";

export function SearchAdd({ onOpen }: { onOpen: (id: Id<"people">) => void }) {
  const [query, setQuery] = useState("");
  const results = useQuery(api.people.searchPeople, { query }) ?? [];
  const addPerson = useMutation(api.people.addPerson);

  const trimmed = query.trim();
  const hasExact = results.some(
    (p) => p.name.toLowerCase() === trimmed.toLowerCase(),
  );

  return (
    <div className="search-add">
      <input
        className="search-box"
        placeholder="Search a name, or type a new one"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        autoFocus
      />
      <ul className="results">
        {results.map((p) => (
          <li key={p._id}>
            <button className="result-row" onClick={() => onOpen(p._id)}>
              {p.name}
            </button>
          </li>
        ))}
      </ul>
      {trimmed !== "" && !hasExact && (
        <button
          className="add-button"
          onClick={async () => {
            const id = await addPerson({ name: trimmed });
            onOpen(id);
          }}
        >
          Add "{trimmed}"
        </button>
      )}
    </div>
  );
}
