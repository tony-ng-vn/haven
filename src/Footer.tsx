// The compliance footer shared by the three public pages: the landing hero,
// Your Sky, and the iOS waitlist page. Links to the site's existing legal and
// support documents -- privacy and terms are the two the App Store asks for
// before it will take a submission (see LegalPage.tsx), support is the App
// Store Connect Support URL (see SupportPage.tsx). All three routes are
// pathname-based ("/privacy", "/terms", "/support") and resolve signed out:
// resolveView checks sitePageFromPath ahead of the auth test in lib.ts,
// specifically so a stranger (or an App Review reviewer with no session) can
// always reach them.
//
// No new legal text lives here -- only links to what already exists, plus a
// plain copyright line.
export function Footer() {
  return (
    <footer className="site-footer">
      <nav className="site-footer-links" aria-label="Legal">
        <a href="/privacy">Privacy</a>
        <a href="/terms">Terms</a>
        <a href="/support">Support</a>
      </nav>
      <p className="site-footer-copyright">(c) 2026 Haven</p>
    </footer>
  );
}
