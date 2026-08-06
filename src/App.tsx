import { useEffect, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { SignIn as ClerkSignIn, useClerk } from "@clerk/react";
import { useConvexAuth } from "convex/react";
import type { Id } from "../convex/_generated/dataModel";
import { SearchAdd } from "./SearchAdd";
import { PersonDetail } from "./PersonDetail";
import { CaptureTriage } from "./CaptureTriage";
import { FeedbackWidget } from "./FeedbackWidget";
import { DriftSky } from "./DriftSky";
import {
  isClerkFlowHash,
  handleFromPath,
  hashRedirectTarget,
  legalDocFromPath,
  resolveView,
  type PersonSnapshot,
} from "./lib";
import { CardPage } from "./CardPage";
import { LegalPage } from "./LegalPage";
import { CLERK_ROUTING } from "./clerkConfig";
import { SupportPage } from "./SupportPage";
import { SkyPage } from "./SkyPage";
import { IosPage } from "./IosPage";
import { Landing2Page } from "./Landing2Page";

function ChevronLeft() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M14.5 5.5 8 12l6.5 6.5"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

// The landing's content: brand, tagline, and the one glass button. Factored out
// so it can double as Clerk's `fallback` in a busy state -- tapping "Sign in"
// before Clerk has loaded holds here on a quiet busy button instead of dropping
// the person into an empty card.
function SkyLanding({ busy, onEnter }: { busy: boolean; onEnter?: () => void }) {
  return (
    <>
      <span className="auth-brand">Haven</span>
      <p className="auth-tagline">Find your way back to the people you meet.</p>
      <button
        className="sky-cta"
        type="button"
        onClick={onEnter}
        disabled={busy}
        aria-busy={busy}
        style={busy ? { opacity: 0.6, cursor: "default" } : undefined}
      >
        {busy ? "Signing in" : "Sign in"}
      </button>
    </>
  );
}

// The signed-out view opens on Haven's own sky -- a glass button over the deep
// field -- and only reveals Clerk's card once the person chooses to enter, so
// we never drop them straight into a third-party form.
function SignIn() {
  // Returning from an OAuth redirect (e.g. "#/sso-callback") must mount Clerk
  // right away to finish sign-in; a first-time visitor mounts it only on tap.
  const [flow] = useState(() => isClerkFlowHash(window.location.hash));
  const [tapped, setTapped] = useState(false);
  return (
    <div className="auth auth-sky">
      <DriftSky className="wl-sky" />
      <div className="auth-sky-content">
        {flow || tapped ? (
          // Clerk holds on `fallback` until its script loads and the card
          // mounts, so an early tap is never a dead click into an empty form;
          // once ready it swaps the busy landing for the real card in place.
          <ClerkSignIn routing={CLERK_ROUTING} fallback={<SkyLanding busy />} />
        ) : (
          <SkyLanding busy={false} onEnter={() => setTapped(true)} />
        )}
      </div>
    </div>
  );
}

type Screen =
  | { kind: "search" }
  | { kind: "capture" }
  | { kind: "detail"; id: Id<"people">; initial: PersonSnapshot | null };

// Wrap a state change in a view transition when the platform offers one and
// the user has not asked for reduced motion; otherwise apply it directly.
export function withScreenTransition(update: () => void, done?: () => void) {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (
    typeof document.startViewTransition !== "function" ||
    reduceMotion ||
    document.visibilityState === "hidden" // nothing to animate off-screen
  ) {
    update();
    done?.();
    return;
  }
  const transition = document.startViewTransition(() => {
    flushSync(update);
  });
  // A skipped or aborted transition (hidden tab, rapid re-entry) rejects
  // `finished`; that is normal, so swallow it and always run the cleanup.
  void transition.finished
    .catch(() => {})
    .then(() => done?.());
}

function Home() {
  const { signOut } = useClerk();
  const [screen, setScreen] = useState<Screen>({ kind: "search" });
  const [query, setQuery] = useState("");
  // The person whose row carries the shared name morph. Set before opening
  // (so the outgoing screen has the source) and kept through closing (so the
  // returning screen has the target), then cleared.
  const [morphId, setMorphId] = useState<Id<"people"> | null>(null);
  const [scrolled, setScrolled] = useState(false);
  const sentinelRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (sentinel === null) return;
    const observer = new IntersectionObserver(([entry]) =>
      setScrolled(!entry.isIntersecting),
    );
    observer.observe(sentinel);
    return () => observer.disconnect();
  }, []);

  function open(person: PersonSnapshot) {
    // Name the tapped row before the old screen is captured.
    flushSync(() => setMorphId(person._id));
    withScreenTransition(() =>
      setScreen({ kind: "detail", id: person._id, initial: person }),
    );
  }

  function close(saved: boolean) {
    withScreenTransition(
      () => {
        setScreen({ kind: "search" });
        if (saved) setQuery("");
      },
      () => setMorphId(null),
    );
  }

  function openCapture() {
    withScreenTransition(() => setScreen({ kind: "capture" }));
  }

  return (
    <>
      <div ref={sentinelRef} className="scroll-sentinel" aria-hidden="true" />
      <header className="app-header" data-scrolled={scrolled ? "true" : "false"}>
        <div className="header-inner">
          {screen.kind === "search" ? (
            <>
              <span className="brand">Haven</span>
              <button className="btn-ghost" type="button" onClick={() => void signOut()}>
                Sign out
              </button>
            </>
          ) : (
            <button className="btn-ghost" type="button" onClick={() => close(false)}>
              <ChevronLeft />
              Back
            </button>
          )}
        </div>
      </header>
      <main
        className={
          screen.kind === "search" ? "app-main app-main-atlas" : "app-main"
        }
      >
        {screen.kind === "search" && (
          <div className="screen" key="search">
            <SearchAdd
              query={query}
              onQueryChange={setQuery}
              onOpen={open}
              onOpenCapture={openCapture}
              morphId={morphId}
            />
          </div>
        )}
        {screen.kind === "capture" && (
          <div className="screen" key="capture">
            <CaptureTriage />
          </div>
        )}
        {screen.kind === "detail" && (
          <div className="screen" key={screen.id}>
            <PersonDetail
              id={screen.id}
              initial={screen.initial}
              onSaved={() => close(true)}
            />
          </div>
        )}
      </main>
      <FeedbackWidget />
    </>
  );
}

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
  if (view === "sky") return <SkyPage />;
  if (view === "waitlist") return <IosPage />;
  if (view === "home") return <Home />;
  if (view === "signin") return <SignIn />;
  if (view === "splash") return <Splash />;
  // "landing2" and everything resolveView falls back to (the bare root
  // included) land here -- Landing2 is the front door.
  return <Landing2Page />;
}
