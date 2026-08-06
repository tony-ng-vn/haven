// The minimal nav shared by the three public pages (the landing hero, Your
// Sky, and the iOS waitlist page): the wordmark left, three plain-text links
// right. No pills, no background of its own -- it reads directly on the dark
// sky behind it, wherever that page's own DriftSky sits.
//
// Absolutely positioned so it drops onto any positioning context (the
// landing hero's `position: relative` box, or the other pages' `position:
// fixed` .card-page) without needing to know which.
//
// Two opt-in props, both defaulting to the shape every existing caller
// already renders, so root, /landing, and iOS keep this anchor exactly as
// before with no props at all:
// - icon defaults to false; only Landing2Page opts in, to sit the Haven
//   mascot next to the wordmark. The icon+text row layout lives under
//   .landing2 .top-nav-brand in index.css rather than a modifier class here,
//   since Landing2Page is the only caller today and the ancestor selector
//   already guarantees no other page's markup or style can shift.
// - links defaults to true; only Sky opts out (links={false}). Of the
//   cluster's three destinations, "Your Sky" is moot (already the page you
//   are on) and "iPhone" is covered by the page's own second hero CTA;
//   "Sign in" is not covered by anything and is intentionally dropped here,
//   not offered elsewhere on this page -- the wordmark, which stays either
//   way, is the way back to it (via root).
export function TopNav({
  icon = false,
  links = true,
}: {
  icon?: boolean;
  links?: boolean;
}) {
  return (
    <header className="top-nav">
      <a className="top-nav-brand" href="/">
        {icon ? <img className="top-nav-icon" src="/icon-192.png" alt="" /> : null}
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
