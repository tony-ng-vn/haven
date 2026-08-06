import { useEffect, useRef, useState } from "react";
import { DriftSky } from "./DriftSky";
import { TopNav } from "./TopNav";
import { SkyDemoEmbed } from "./SkyDemoEmbed";
import { Footer } from "./Footer";

// inhavens.com/landing, signed out.
//
// A polished copy of the default landing (LandingPage.tsx) for the owner to
// compare side by side: identical content, structure, copy, CTAs, DriftSky
// hero and reused components -- only the type, motion, and focus treatment
// are elevated, all of it scoped under the "landing-polished" class on the
// root element so nothing here can bleed into the untouched default (see
// index.css's own ".landing-polished" section, and driftSkyCanvasSizing's
// .landing-sky host class, reused as-is rather than duplicated).
//
// LandingPage.tsx itself, its test, and every style it uses stay
// byte-identical to main -- this file exists so a changed mind never has to
// touch either.
function prefersFinePointer(): boolean {
  return (
    typeof window !== "undefined" &&
    window.matchMedia("(hover: hover) and (pointer: fine)").matches
  );
}

// A below-fold section's own reveal: invisible until it has been seen once,
// then settled -- see the "once" comment on the observer below. Local to this
// file since nothing else needs it yet; LandingPage's sections do not get
// this treatment (byte-identical to main), and Landing2Page's single hero has
// no below-fold content of its own to reveal.
function useRevealOnScroll<T extends HTMLElement>() {
  const ref = useRef<T | null>(null);
  const [revealed, setRevealed] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (el === null) return;
    // happy-dom (this repo's test environment) has no IntersectionObserver at
    // all -- rather than stay invisible forever there, and on any real
    // browser old enough to lack it, show the section plainly instead of
    // gating content behind an API that might not exist.
    if (typeof IntersectionObserver === "undefined") {
      setRevealed(true);
      return;
    }
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        setRevealed(true);
        // Once semantics: the reveal is a first-sight moment, not a repeating
        // scroll effect -- see the motion spec's "no parallax, no continuous
        // motion".
        observer.disconnect();
      }
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return { ref, revealed };
}

export function PolishedLandingPage() {
  // Same read-once reasoning as LandingPage's own prefersFinePointer: a
  // device's pointer type does not change mid-session.
  const [interactive] = useState(prefersFinePointer);
  // Written straight to the DOM via a ref rather than React state: this
  // attribute only ever drives a CSS transition
  // (".landing-polished[data-mounted] ..." in index.css), so flipping it
  // through setState would re-render -- and re-mount the stubbed DriftSky in
  // this file's own tests -- for no purpose a style attribute doesn't already
  // serve. useEffect (not useLayoutEffect) is what makes this safe to set
  // unconditionally: it runs after the browser has already painted the rest
  // state, so the transition always has a "from" frame.
  const rootRef = useRef<HTMLDivElement | null>(null);
  const skySection = useRevealOnScroll<HTMLElement>();
  const iosSection = useRevealOnScroll<HTMLElement>();

  useEffect(() => {
    document.title = "Haven - Landing";
  }, []);

  useEffect(() => {
    rootRef.current?.setAttribute("data-mounted", "true");
  }, []);

  return (
    <div className="landing landing-polished" ref={rootRef}>
      {/* Same full-page fixed canvas as the default landing, and the same
          host class -- see .landing-sky in index.css, and
          driftSkyCanvasSizing.test.ts, which already pins its sizing. */}
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
              Sky app, coming soon
            </a>
            <a className="landing-cta-secondary" href="#/ios">
              Join the iPhone waitlist
            </a>
          </div>
          <p className="landing-hero-note">Free, runs on your Mac.</p>
        </div>
      </section>

      <section
        ref={skySection.ref}
        className={`landing-section${skySection.revealed ? " landing-polished-in-view" : ""}`}
        aria-label="Your Sky, for Mac"
      >
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

      <section
        ref={iosSection.ref}
        className={`landing-section${iosSection.revealed ? " landing-polished-in-view" : ""}`}
        aria-label="Haven, for iPhone"
      >
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
