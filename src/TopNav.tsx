// The minimal nav shared by the three public pages (the landing hero, Your
// Sky, and the iOS waitlist page): the wordmark left, three plain-text links
// right. No pills, no background of its own -- it reads directly on the dark
// sky behind it, wherever that page's own DriftSky sits.
//
// Absolutely positioned so it drops onto any positioning context (the
// landing hero's `position: relative` box, or the other pages' `position:
// fixed` .card-page) without needing to know which.
export function TopNav() {
  return (
    <header className="top-nav">
      <a className="top-nav-brand" href="/">
        Haven
      </a>
      <nav className="top-nav-links" aria-label="Haven">
        <a href="#/sky">Your Sky</a>
        <a href="#/ios">iPhone</a>
        <a href="#/sign-in">Sign in</a>
      </nav>
    </header>
  );
}
