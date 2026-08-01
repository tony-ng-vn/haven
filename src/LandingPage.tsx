import { useEffect, useState } from "react";
import { DriftSky } from "./DriftSky";
import { TopNav } from "./TopNav";
import { SkyDemoEmbed } from "./SkyDemoEmbed";
import { Footer } from "./Footer";

// inhavens.com/, signed out.
//
// The Haven landing: the drifting, constellation-lit sky fills the entire
// page as a fixed background layer -- not just the hero -- so scrolling past
// the fold never hits flat dark, the same full-bleed feel the old waitlist
// page had for its one screen, now carried the whole page's length. On top
// of it: a full-viewport hero (headline, subline, the two product CTAs),
// then full-width sections introducing each product, then the compliance
// footer. Replaces the old two-card landing the owner rejected on preview: a
// small corner of text over a sea of empty dark that nobody clicked into --
// and before that, a hero whose sky was pinned to a tiny top-left square (see
// .landing-sky in index.css for the canvas-sizing bug that caused it).
//
// The hero owns the constellation lens: the figure and its own wander are on
// unconditionally, on every device, matching the old full-page waitlist
// (waitlist-design.md: "a phone is always wandering until a finger presses
// the page"). Only the drag-to-reveal GESTURE -- pointer tracking, and
// specifically the non-passive touchmove that would otherwise fight this
// page's own scroll -- is limited to a fine pointer; see prefersFinePointer
// below and gestureEnabled in lens.ts. Restored here from src/lens.ts and
// DriftSky's lens path, which had gone unused once the old full-page waitlist
// that was their only caller was removed.
function prefersFinePointer(): boolean {
  return (
    typeof window !== "undefined" &&
    window.matchMedia("(hover: hover) and (pointer: fine)").matches
  );
}

export function LandingPage() {
  // Read once, like WaitlistForm's own initialMode(): a device's pointer
  // type does not change mid-session, so this decides whether the drag
  // gesture is worth wiring up at all -- not a layout choice, whether the
  // gesture itself attaches. A coarse pointer still gets the figure
  // appearing and drifting on its own (see DriftSky's lens path); it just
  // never gets the listener that would block scroll under a touch drag.
  // DriftSky's own reduced-motion check still applies underneath all of
  // this: a visitor who prefers reduced motion gets neither the wander nor
  // the drag figure, fine pointer or not.
  const [interactive] = useState(prefersFinePointer);

  useEffect(() => {
    document.title = "Haven - A memory layer for the people you meet";
  }, []);

  return (
    <div className="landing">
      {/* One canvas for the whole page, not one per section -- a second
          instance would double the animation cost for no visible gain once
          this one already covers the viewport as a fixed layer. */}
      <DriftSky className="landing-sky" lens interactive={interactive} />

      <section className="landing-hero">
        <TopNav />
        <div className="landing-hero-content">
          <h1 className="landing-hero-title">Your people are a constellation.</h1>
          <p className="landing-hero-sub">
            Haven keeps a memory of the people you meet, so you can find them
            again when a name escapes you.
          </p>
          <div className="landing-hero-ctas">
            <a className="sky-download" href="#/sky">
              Try Your Sky for Mac
            </a>
            <a className="landing-cta-secondary" href="#/ios">
              Join the iPhone waitlist
            </a>
          </div>
          <p className="landing-hero-note">Free, runs on your Mac.</p>
        </div>
      </section>

      <section className="landing-section" aria-label="Your Sky, for Mac">
        <h2 className="landing-section-title">Your Sky, for Mac</h2>
        <p className="landing-section-body">
          Your Sky reads your own iMessage history and Contacts locally on
          your Mac, and draws everyone you actually talk to as a map you can
          explore.
        </p>
        <SkyDemoEmbed />
        <a className="sky-download" href="#/sky">
          Get Your Sky for Mac
        </a>
      </section>

      <section className="landing-section" aria-label="Haven, for iPhone">
        <h2 className="landing-section-title">Haven, for iPhone</h2>
        <p className="landing-section-body">
          Connect with someone in one tap, and find them again later by any
          detail you remember. Haven for iPhone is still in development.
        </p>
        <a className="landing-cta-secondary" href="#/ios">
          Join the waitlist
        </a>
      </section>

      <Footer />
    </div>
  );
}
