import { useEffect, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { SignInButton, useClerk } from "@clerk/react";
import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import type { Id } from "../convex/_generated/dataModel";
import { SearchAdd } from "./SearchAdd";
import { PersonDetail } from "./PersonDetail";
import { CaptureTriage } from "./CaptureTriage";
import type { PersonSnapshot } from "./lib";

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

// Clerk's own modal handles sign-in, sign-up, and error states, so this
// keeps only the Quiet Room shell (brand, tagline, card) around its trigger.
function SignIn() {
  return (
    <div className="auth">
      <div className="auth-card">
        <span className="auth-brand">Euno</span>
        <p className="auth-tagline">Find your way back to the people you meet.</p>
        <SignInButton mode="modal">
          <button className="btn-primary auth-submit" type="button">
            Sign in
          </button>
        </SignInButton>
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
function withScreenTransition(update: () => void, done?: () => void) {
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
      <main className="app-main">
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
    </>
  );
}

export default function App() {
  return (
    <>
      <AuthLoading>
        <div className="splash">
          <span className="splash-brand">Euno</span>
        </div>
      </AuthLoading>
      <Unauthenticated>
        <SignIn />
      </Unauthenticated>
      <Authenticated>
        <Home />
      </Authenticated>
    </>
  );
}
