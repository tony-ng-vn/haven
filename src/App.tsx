import { useEffect, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { SignIn as ClerkSignIn, useClerk } from "@clerk/react";
import { useConvexAuth } from "convex/react";
import type { Id } from "../convex/_generated/dataModel";
import { SearchAdd } from "./SearchAdd";
import { PersonDetail } from "./PersonDetail";
import { CaptureTriage } from "./CaptureTriage";
import { PersonSky } from "./PersonSky";
import { FeedbackWidget } from "./FeedbackWidget";
import {
  bootMode,
  isClerkFlowHash,
  type BootMode,
  type PersonSnapshot,
} from "./lib";

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
      <span className="auth-brand">Euno</span>
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

// The signed-out view opens on Euno's own sky -- a glass button over the deep
// field -- and only reveals Clerk's card once the person chooses to enter, so
// we never drop them straight into a third-party form.
function SignIn() {
  // Returning from an OAuth redirect (e.g. "#/sso-callback") must mount Clerk
  // right away to finish sign-in; a first-time visitor mounts it only on tap.
  const [flow] = useState(() => isClerkFlowHash(window.location.hash));
  const [tapped, setTapped] = useState(false);
  return (
    <div className="auth auth-sky">
      <div className="sky-space" aria-hidden="true" />
      <PersonSky name="Euno" />
      <div className="sky-vignette" aria-hidden="true" />
      <div className="auth-sky-content">
        {flow || tapped ? (
          // Clerk holds on `fallback` until its script loads and the card
          // mounts, so an early tap is never a dead click into an empty form;
          // once ready it swaps the busy landing for the real card in place.
          <ClerkSignIn fallback={<SkyLanding busy />} />
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
              <span className="brand">Euno</span>
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
      <span className="splash-brand">Euno</span>
    </div>
  );
}

// A durable breadcrumb that this browser has signed in before. It lets a
// returning visitor splash straight toward the app instead of flashing the
// landing while Clerk wakes. Reads can fail (private mode); we degrade to "no
// hint" rather than throw, so those visitors just meet the landing first.
const SESSION_HINT_KEY = "euno:hasSession";

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
  // The boot decision reads the hash and hint once, at first paint -- that frame
  // is the whole point, since it renders before Clerk can weigh in. After auth
  // resolves we follow the live Convex state, so a stale mode never matters.
  const [mode] = useState<BootMode>(() =>
    bootMode({
      hash: window.location.hash,
      hasSessionHint: readSessionHint(),
    }),
  );

  // Keep the hint honest against the resolved auth state: set it when signed in,
  // clear it the moment we resolve signed out -- covering both a sign-out and a
  // stale hint whose session no longer holds (which then self-heals to the
  // landing on the next boot). Left untouched while auth is still loading.
  useEffect(() => {
    if (isLoading) return;
    writeSessionHint(isAuthenticated);
  }, [isLoading, isAuthenticated]);

  if (isAuthenticated) return <Home />;
  // A returning visitor or an in-flight Clerk callback waits on the splash;
  // only a first-time visitor gets the landing painted before Clerk loads. The
  // signed-out resolved state falls through to the same <SignIn/>, so a
  // pre-Clerk tap on the landing is preserved across the flip -- no remount.
  if (isLoading && mode !== "landing") return <Splash />;
  return <SignIn />;
}
