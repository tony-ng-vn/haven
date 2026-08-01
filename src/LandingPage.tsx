import { useEffect, useState } from "react";
import { DriftSky } from "./DriftSky";
import { TopNav } from "./TopNav";
import { SkyDemoEmbed } from "./SkyDemoEmbed";

// inhavens.com/, signed out.
//
// The Haven landing: a full-viewport hero that puts the product's own world
// on screen -- the drifting, constellation-lit sky at full presence, not the
// dimmed 0.55 the other public pages use -- then two full-width sections
// introducing each product and a quiet footer. Replaces the old two-card
// landing the owner rejected on preview: a small corner of text over a sea of
// empty dark that nobody clicked into.
//
// The hero owns the constellation lens (see prefersFinePointer below): the
// drag-to-reveal figure is the page's thesis made into a gesture, restored
// here from src/lens.ts and DriftSky's lens path, which had gone unused once
// the old full-page waitlist that was its only caller was removed.
function prefersFinePointer(): boolean {
  return (
    typeof window !== "undefined" &&
    window.matchMedia("(hover: hover) and (pointer: fine)").matches
  );
}

export function LandingPage() {
  // Read once, like WaitlistForm's own initialMode(): this decides whether
  // the drag gesture is worth wiring up at all, not something that needs to
  // track a live device change mid-session. A touch device falls back to the
  // plain drift DriftSky already does without the lens -- the same split the
  // old full-page waitlist had between desktop and phone, now gating the
  // gesture itself rather than a layout. DriftSky's own reduced-motion check
  // still applies underneath this: a fine-pointer visitor who prefers reduced
  // motion gets neither the wander nor the drag figure.
  const [lens] = useState(prefersFinePointer);

  useEffect(() => {
    document.title = "Haven - A memory layer for the people you meet";
  }, []);

  return (
    <div className="landing">
      <section className="landing-hero">
        <DriftSky className="landing-hero-sky" lens={lens} />
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

      <footer className="landing-footer">
        <a href="/privacy">Privacy</a>
        <a href="/terms">Terms</a>
        <a href="/support">Support</a>
      </footer>
    </div>
  );
}
