import { useState } from "react";

// A live, click-to-activate look at what Your Sky draws: /demo-sky.html is a
// given file (see vercel.json for the narrower policy it needs to run at
// all) -- a single self-contained page built from the real viewer, seeded
// with entirely invented people. Never edited here; only linked to.
const DEMO_SRC = "/demo-sky.html";

// A pan-and-zoom canvas competes with the page's own scroll and has little
// room to work with inside a small iframe, so a narrow viewport gets a direct
// link that opens the demo in its own tab instead of an inline swap. Read
// once at mount, matching the rest of the site's viewport checks (e.g.
// WaitlistForm's own desktop/phone split) -- this decides which affordance to
// show, not something that needs to track a live resize.
const SMALL_SCREEN = 620;

function isSmallScreen(): boolean {
  return typeof window !== "undefined" && window.innerWidth < SMALL_SCREEN;
}

export function SkyDemoEmbed() {
  const [small] = useState(isSmallScreen);
  const [activated, setActivated] = useState(false);

  return (
    <div className="demo-embed">
      {small ? (
        <a
          className="demo-panel"
          href={DEMO_SRC}
          target="_blank"
          rel="noopener noreferrer"
        >
          <span className="sky-cta">Explore a sample sky</span>
        </a>
      ) : activated ? (
        <iframe
          className="demo-frame"
          src={DEMO_SRC}
          title="A sample sky, invented people"
        />
      ) : (
        <button
          type="button"
          className="demo-panel"
          onClick={() => setActivated(true)}
        >
          <span className="sky-cta">Explore a sample sky</span>
        </button>
      )}
      <p className="demo-caption">A sample sky, invented people.</p>
    </div>
  );
}
