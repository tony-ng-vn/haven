// The minimal nav shared by the three public pages (the landing hero, Your
// Sky, and the iOS waitlist page): the wordmark left, three plain-text links
// right. No pills, no background of its own -- it reads directly on the dark
// sky behind it, wherever that page's own DriftSky sits.
//
// Absolutely positioned so it drops onto any positioning context (the
// landing hero's `position: relative` box, or the other pages' `position:
// fixed` .card-page) without needing to know which.
//
// icon defaults to false so every existing caller -- root, /landing, Sky,
// iOS -- renders this anchor exactly as before; only Landing2Page opts in,
// to sit the Haven mascot next to the wordmark. The icon+text row layout
// lives under .landing2 .top-nav-brand in index.css rather than a modifier
// class here, since Landing2Page is the only caller today and the ancestor
// selector already guarantees no other page's markup or style can shift.
export function TopNav({ icon = false }: { icon?: boolean }) {
  return (
    <header className="top-nav">
      <a className="top-nav-brand" href="/">
        {icon ? <img className="top-nav-icon" src="/icon-192.png" alt="" /> : null}
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
