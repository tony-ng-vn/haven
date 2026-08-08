import { useEffect, useState } from "react";
import { useConvexAuth } from "convex/react";
import {
  handleFromPath,
  hashRedirectTarget,
  legalDocFromPath,
  resolveView,
} from "./lib";
import { CardPage } from "./CardPage";
import { LegalPage } from "./LegalPage";
import { SupportPage } from "./SupportPage";
import { IosPage } from "./IosPage";
import { Landing2Page } from "./Landing2Page";
import { PreviewPortal } from "./PreviewPortal";

function Splash() {
  return (
    <div className="splash">
      <span className="splash-brand">Haven</span>
    </div>
  );
}

// A durable breadcrumb that this browser has signed in before. It lets a
// returning visitor splash straight toward the app instead of flashing the
// landing while Clerk wakes. Reads can fail (private mode); we degrade to "no
// hint" rather than throw, so those visitors just meet the landing first.
const SESSION_HINT_KEY = "haven:hasSession";

function readSessionHint(): boolean {
  try {
    return window.localStorage.getItem(SESSION_HINT_KEY) !== null;
  } catch {
    return false;
  }
}

function writeSessionHint(present: boolean): void {
  try {
    if (present) window.localStorage.setItem(SESSION_HINT_KEY, "1");
    else window.localStorage.removeItem(SESSION_HINT_KEY);
  } catch {
    // Storage blocked -- the returning-visitor fast path simply won't apply.
  }
}

export default function App() {
  const { isLoading, isAuthenticated } = useConvexAuth();

  // The hash is tracked live so navigating between the site's hash routes
  // (or the back button) re-routes in place, without a reload.
  const [hash, setHash] = useState(() => window.location.hash);
  useEffect(() => {
    const onHashChange = () => setHash(window.location.hash);
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  // Old hash links ("#/sky", "#/ios", "#/join", "#/landing2") still out in
  // the world -- shared urls, bookmarks -- get canonicalized onto their new
  // pathname with a real redirect rather than quietly resolving to the same
  // content at two addresses (bad for both a person's address bar and search
  // indexing). location.replace is a full navigation, not a SPA transition,
  // by design: it lets the browser and the URL bar agree with what actually
  // rendered, the same way a server-side redirect would. resolveView's own
  // hashRedirectTarget check keeps the one frame before this effect runs from
  // reading as an OAuth callback instead.
  useEffect(() => {
    const target = hashRedirectTarget(hash);
    if (target !== null) window.location.replace(target);
  }, [hash]);

  // Read once at first paint -- it only steers the frame before Clerk resolves;
  // after that, isAuthenticated drives the choice.
  const [hasSessionHint] = useState(readSessionHint);

  // Keep the hint honest against the resolved auth state: set it when signed in,
  // clear it the moment we resolve signed out -- covering both a sign-out and a
  // stale hint whose session no longer holds. Left untouched while auth loads.
  useEffect(() => {
    if (isLoading) return;
    writeSessionHint(isAuthenticated);
  }, [isLoading, isAuthenticated]);

  // Read once, unlike the hash: nothing in the app navigates between paths, so
  // a card url only ever arrives as a fresh load.
  const [pathname] = useState(() => window.location.pathname);

  const view = resolveView({
    isAuthenticated,
    isLoading,
    hash,
    hasSessionHint,
    pathname,
  });
  if (view === "card") {
    // Non-null whenever resolveView says card, by the same check.
    return <CardPage handle={handleFromPath(pathname)!} />;
  }
  if (view === "legal") {
    // Non-null whenever resolveView says legal, by the same check.
    return <LegalPage doc={legalDocFromPath(pathname)!} />;
  }
  if (view === "support") return <SupportPage />;
  if (view === "waitlist") return <IosPage />;
  if (view === "festival") return <Landing2Page festival />;
  if (view === "preview") {
    return (
      <PreviewPortal
        pathname={pathname}
        hash={hash}
        isAuthenticated={isAuthenticated}
        isLoading={isLoading}
      />
    );
  }
  if (view === "splash") return <Splash />;
  // "landing2" and everything resolveView falls back to (the bare root
  // included) land here -- Landing2 is the front door.
  return <Landing2Page />;
}
