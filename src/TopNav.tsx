// The minimal nav shared by every public page (the waitlist root, Your Sky,
// the iOS product page, and both landing concepts): the Haven mascot and
// wordmark, left, linking home. Nothing else -- no pills, no background of
// its own -- it reads directly on the dark sky behind it, wherever that
// page's own DriftSky sits.
//
// Absolutely positioned so it drops onto any positioning context (a
// `position: relative` hero, or the other pages' `position: fixed`
// .card-page) without needing to know which.
//
// The mascot icon used to be opt-in, added only for Landing2Page's own
// glass-hero composition; the owner then asked for it on every page, and
// bigger, so it is now unconditional.
//
// The "Your Sky / iPhone / Sign in" links cluster that used to sit to the
// right of the wordmark is gone -- the owner asked for it removed twice, and
// the second time asked for it gone everywhere, not opted out of per page.
// There is no prop left to configure it back in: this component is
// brand-only, full stop, on every caller. Each page's own CTAs carry the
// navigation onward now (Sky's and Landing2's hero buttons, the landing
// pages' two product sections); sign-in is reachable only by typing
// "#/sign-in" directly, an owner-accepted consequence of dropping the last
// link that pointed at it.
export function TopNav() {
  return (
    <header className="top-nav">
      <a className="top-nav-brand" href="/">
        <img className="top-nav-icon" src="/icon-nav.png" alt="" />
        Haven
      </a>
    </header>
  );
}
