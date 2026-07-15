import { useQuery, useMutation } from "convex/react";
import { useEffect, useState } from "react";
import { api } from "../convex/_generated/api";
import type { Id } from "../convex/_generated/dataModel";

export function PersonDetail({
  id,
  onSaved,
}: {
  id: Id<"people">;
  onSaved: () => void;
}) {
  const person = useQuery(api.people.getPerson, { id });
  const updatePerson = useMutation(api.people.updatePerson);
  const [link, setLink] = useState("");
  const [context, setContext] = useState("");

  // Hydrate the form once the person loads.
  useEffect(() => {
    if (person) {
      setLink(person.link ?? "");
      setContext(person.context ?? "");
    }
  }, [person?._id]);

  if (person === undefined) return <p>Loading...</p>;
  if (person === null) {
    return (
      <div>
        <p>That person is not available.</p>
        <button onClick={onSaved}>Back</button>
      </div>
    );
  }

  return (
    <div className="person-detail">
      <h1>{person.name}</h1>
      <label>
        Link
        <input
          type="url"
          placeholder="https://..."
          value={link}
          onChange={(e) => setLink(e.target.value)}
        />
      </label>
      <label>
        Context
        <textarea
          placeholder="How you met, what they are working on, anything you want to remember"
          value={context}
          onChange={(e) => setContext(e.target.value)}
        />
      </label>
      <div className="actions">
        <button onClick={onSaved}>Back</button>
        <button
          className="save"
          onClick={async () => {
            await updatePerson({
              id,
              link: link.trim() === "" ? undefined : link.trim(),
              context: context.trim() === "" ? undefined : context.trim(),
            });
            onSaved();
          }}
        >
          Save
        </button>
      </div>
    </div>
  );
}
