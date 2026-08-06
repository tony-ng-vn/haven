// The minimal nav shared by every public page (the landing hero, Your Sky,
// and the iOS waitlist page): the Haven mascot and wordmark left, three
// plain-text links right. No pills, no background of its own -- it reads
// directly on the dark sky behind it, wherever that page's own DriftSky
// sits.
//
// Absolutely positioned so it drops onto any positioning context (the
// landing hero's `position: relative` box, or the other pages' `position:
// fixed` .card-page) without needing to know which.
//
// The mascot icon used to be opt-in, added only for Landing2Page's own
// glass-hero composition; the owner then asked for it on every page, and
// bigger, so it is now unconditional -- there is no prop left to turn it
// off.
//
// One remaining opt-in prop:
// - links defaults to true; Sky and Landing2 opt out (links={false}). On
//   Sky, of the cluster's three destinations, "Your Sky" is moot (already
//   the page you are on) and "iPhone" is covered by the page's own second
//   hero CTA; on Landing2 the owner wants nothing sitting on top of the
//   glass artwork, and its own two hero CTAs cover the same ground. "Sign
//   in" is not covered by anything on either page and is intentionally
//   dropped, not offered elsewhere -- the wordmark, which stays either way,
//   is the way back to it (via root).
export function TopNav({ links = true }: { links?: boolean }) {
  return (
    <header className="top-nav">
      <a className="top-nav-brand" href="/">
        <img className="top-nav-icon" src="/icon-192.png" alt="" />
        Haven
      </a>
      {links ? (
        <nav className="top-nav-links" aria-label="Haven">
          <a href="#/sky">Your Sky</a>
          <a href="#/ios">iPhone</a>
          <a href="#/sign-in">Sign in</a>
        </nav>
      ) : null}
    </header>
  );
}
