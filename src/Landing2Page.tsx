import { useEffect, useRef, useState } from "react";
import { DriftSky } from "./DriftSky";
import { TopNav } from "./TopNav";
import { Footer } from "./Footer";

// inhavens.com/#/landing2, linked from nowhere.
//
// A second concept for the front door, evaluated alongside the default
// landing and the polished preview: a single-viewport hero built around the
// owner's own generated art (public/glass-hero.jpg) rather than an
// approximation of it. The previous version of this page drew broken glass,
// a hidden world, and a hover/tap reveal entirely in CSS and SVG; the owner
// compared it to the real image and rejected the CSS approximation. This
// version does not approximate anything -- the image IS the page, fused with
// the flat page navy behind it by one blend gradient (see .landing2-art in
// index.css). The navy left also now carries the same drifting,
// constellation-lit sky as the root and polished landings (see DriftSky.tsx):
// the owner wanted this page's own living sky too, not just the art. The
// canvas rides behind the copy column, sized (not just masked) to the navy
// zone -- .landing2-sky in index.css explains why the box itself has to be
// smaller than the hero, not full width with a mask painted over the art.
//
// .landing-polished (see index.css) is reused wholesale on the root, not
// duplicated: Satoshi, the press/hover/focus treatment on the shared
// .sky-download / .landing-cta-secondary / TopNav classes, and the
// [data-mounted] entrance mechanism all carry over from the polished
// landing for free.
function prefersFinePointer(): boolean {
  return (
    typeof window !== "undefined" &&
    window.matchMedia("(hover: hover) and (pointer: fine)").matches
  );
}

export function Landing2Page() {
  // Same ref-written mount flag as PolishedLandingPage.tsx (see its own
  // comment for why a ref rather than React state): this page has no below-
  // fold reveal of its own, so a shared hook module would be one export used
  // by exactly two call sites for three lines of logic each -- not worth the
  // indirection yet.
  const rootRef = useRef<HTMLDivElement | null>(null);
  // Same read-once reasoning as LandingPage's own prefersFinePointer: a
  // device's pointer type does not change mid-session. This hero's desktop
  // row layout does not scroll (min-height: 100vh, overflow: hidden), but the
  // narrow stacked layout does -- interactive still only gates the drag
  // gesture's touchmove listener, and a coarse pointer (the only kind that
  // would ever fight that scroll) never gets it, fixed hero or scrolling
  // column alike.
  const [interactive] = useState(prefersFinePointer);

  useEffect(() => {
    document.title = "Haven - Landing 2";
  }, []);

  useEffect(() => {
    rootRef.current?.setAttribute("data-mounted", "true");
  }, []);

  return (
    <div className="landing2 landing-polished" ref={rootRef}>
      <section className="landing2-hero">
        {/* One canvas for this hero, behind the nav, the copy, and the art --
            same reasoning as the full-page landings, scaled to one section
            instead of the whole page. See .landing2-sky in index.css: the
            box is sized to the navy zone rather than full width, so the
            constellation's own wander path never carries it behind the
            artwork. */}
        <DriftSky className="landing2-sky" lens interactive={interactive} />
        <TopNav icon />

        <div className="landing2-copy-col">
          <h1 className="landing2-hero-title">
            Your people{" "}
            <br />
            are a constellation.
          </h1>
          <p className="landing2-hero-sub">
            Each person is beautiful on their own, but too often distant and
            disconnected. Haven helps you remember people, reconnect, and
            bring your world together.
          </p>
          <div className="landing-hero-ctas">
            <a className="sky-download" href="#/sky">
              Sky app, coming soon
            </a>
            <a className="landing-cta-secondary" href="#/ios">
              Join the iPhone waitlist
            </a>
          </div>
          <p className="landing-hero-note">Free, runs on your Mac.</p>
        </div>

        <div className="landing2-art">
          {/* Decorative: the surrounding copy already carries the page's
              whole message, and the art (painterly broken-glass panes, a
              moonlit valley, a galaxy, constellations) adds mood and brand
              rather than information a screen reader user would otherwise
              miss -- an empty alt, not a described one. */}
          <img src="/glass-hero.jpg" alt="" />
        </div>
      </section>

      <Footer />
    </div>
  );
}
