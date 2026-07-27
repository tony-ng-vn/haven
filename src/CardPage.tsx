import { useQuery } from "convex/react";
import { useEffect } from "react";
import { api } from "../convex/_generated/api";
import { PersonSky } from "./PersonSky";

// Where each platform's handle actually lives, so the page can link out rather
// than print a string somebody has to retype.
const PLATFORM_HOME = {
  instagram: { label: "Instagram", prefix: "https://instagram.com/" },
  x: { label: "X", prefix: "https://x.com/" },
  linkedin: { label: "LinkedIn", prefix: "https://linkedin.com/in/" },
} as const;

type Platform = keyof typeof PLATFORM_HOME;

// The public card behind inhavens.com/<handle>: what a stranger sees after
// pointing a camera at somebody's beacon.
//
// Everything here has to work signed out, because signed out is the normal way
// to arrive. The query is public and the page never asks who is reading it.
export function CardPage({ handle }: { handle: string }) {
  const card = useQuery(api.profiles.getByHandle, { handle });

  useEffect(() => {
    if (card === undefined) return;
    document.title = card === null ? "Not on Haven" : `${card.name} on Haven`;
  }, [card]);

  // Undefined is the query in flight; null is a handle nobody holds. They are
  // different answers and the second one is final, so they must not share a
  // spinner.
  if (card === undefined) {
    return (
      <div className="card-page card-page-quiet">
        <p className="card-quiet-line" role="status">
          Loading
        </p>
      </div>
    );
  }

  if (card === null) {
    return (
      <div className="card-page card-page-quiet">
        <h1 className="card-quiet-title">Nobody here</h1>
        <p className="card-quiet-line">
          There is no Haven card at this address.
        </p>
        <a className="card-cta" href="/">
          What is Haven?
        </a>
      </div>
    );
  }

  const cityLine = card.city
    ? [card.city.name, card.city.admin, card.city.country]
        .filter((part) => part !== undefined && part !== "")
        .join(", ")
    : null;

  // primaryPlatform can name a platform whose handle was stripped on the way
  // out -- phone is never published -- so it cannot be assumed to appear in
  // handles. Anyone reaching this person by that route goes through Haven.
  const reachableHere = card.handles.some(
    (entry) => entry.platform === card.primaryPlatform,
  );
  const primaryIsPrivate =
    card.primaryPlatform !== undefined && !reachableHere;

  return (
    <div className="card-page">
      <div className="card-sky" aria-hidden="true">
        <PersonSky name={card.name} handle={card.handle} />
      </div>
      <div className="card-content">
        {card.photoUrl !== null && (
          <img className="card-photo" src={card.photoUrl} alt="" />
        )}
        <h1 className="card-name">{card.name}</h1>
        {cityLine !== null && <p className="card-city">{cityLine}</p>}

        {card.handles.length > 0 && (
          <ul className="card-handles">
            {card.handles.map((entry) => {
              const home = PLATFORM_HOME[entry.platform as Platform];
              return (
                <li key={`${entry.platform}:${entry.value}`}>
                  <a
                    className="card-handle"
                    href={`${home.prefix}${entry.value}`}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {home.label}
                    <span className="card-handle-value">{entry.value}</span>
                  </a>
                </li>
              );
            })}
          </ul>
        )}

        {primaryIsPrivate && (
          <p className="card-quiet-line">
            The rest is on Haven.
          </p>
        )}

        <a className="card-cta" href="/">
          Get your own card
        </a>
      </div>
    </div>
  );
}
