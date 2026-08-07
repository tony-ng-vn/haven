import { useEffect, useRef, useState } from "react";
import { DriftSky } from "./DriftSky";
import { TopNav } from "./TopNav";
import { Footer } from "./Footer";

// inhavens.com/, the front door -- the page a signed-out stranger meets. Its
// own old hash address, "#/landing2", still works too: it redirects here now
// (see hashRedirectTarget in lib.ts and the canonicalizing effect in App.tsx)
// for links still out in the world from when this page was an unlinked
// second concept, reachable only by typing the url.
//
// Built around the owner's own generated art (public/glass-hero.jpg) rather
// than an approximation of it: a single-viewport hero, the copy on the flat
// page navy at left, the art at right. An earlier version of this page drew
// broken glass, a hidden world, and a hover/tap reveal entirely in CSS and
// SVG; the owner compared it to the real image and rejected the CSS
// approximation. This version does not approximate anything -- the image IS
// the page, fused with the flat page navy behind it by one blend gradient
// (see .landing2-art in index.css). The navy left also carries the same
// drifting, constellation-lit sky the site's earlier default landing had
// (see DriftSky.tsx): the owner wanted this page's own living sky too, not
// just the art. The canvas rides behind the copy column, sized (not just
// masked) to the navy zone -- .landing2-sky in index.css explains why the box
// itself has to be smaller than the hero, not full width with a mask painted
// over the art.
//
// .landing-polished (see index.css) is reused wholesale, not duplicated:
// Satoshi, the press/hover/focus treatment on the shared .sky-download /
// .landing-cta-secondary / TopNav classes, and the [data-mounted] entrance
// mechanism. Written for that earlier default landing (its own component
// deleted once the owner picked this page as the front door instead -- see
// resolveView in lib.ts), this page is now that CSS scope's sole home.
function prefersFinePointer(): boolean {
  return (
    typeof window !== "undefined" &&
    window.matchMedia("(hover: hover) and (pointer: fine)").matches
  );
}

export function Landing2Page() {
  // Same ref-written mount flag the earlier landing hero used (see this
  // file's own header comment): a shared hook module would be one export
  // used by a single call site now that page is gone, so it stays local
  // rather than being pulled out for no second caller.
  const rootRef = useRef<HTMLDivElement | null>(null);
  // Read once, not tracked live: a device's pointer type does not change
  // mid-session. This hero's desktop row layout does not scroll (min-height:
  // 100vh, overflow: hidden), but the narrow stacked layout does --
  // interactive still only gates the drag gesture's touchmove listener, and
  // a coarse pointer (the only kind that would ever fight that scroll) never
  // gets it, fixed hero or scrolling column alike.
  const [interactive] = useState(prefersFinePointer);

  useEffect(() => {
    // Exactly index.html's own <title>, not a shorter variant: this page IS
    // the root now, Google renders JS, and the "(Inhavens)" token is the
    // whole point of the brand-SEO title (see seo.test.ts) -- overwriting it
    // with a bare "Haven" would silently undo that on the rendered page.
    document.title = "Haven (Inhavens) - A personal memory layer for your people";
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
        <TopNav />

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
            <a
              className="sky-download"
              href="https://cal.com/tony-nguyen-vn17"
            >
              Book a call
            </a>
            <a className="landing-cta-secondary" href="/waitlist">
              Join the iPhone waitlist
            </a>
          </div>
          <p className="landing-hero-note">
            A conversation about people, memory, and connection.
          </p>
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
