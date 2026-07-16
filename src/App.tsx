import { useEffect, useRef, useState, type FormEvent } from "react";
import { flushSync } from "react-dom";
import { useAuthActions } from "@convex-dev/auth/react";
import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import type { Id } from "../convex/_generated/dataModel";
import { SearchAdd } from "./SearchAdd";
import { PersonDetail } from "./PersonDetail";
import { mapAuthError, type AuthFlow, type PersonSnapshot } from "./lib";

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

function SignIn() {
  const { signIn } = useAuthActions();
  const [flow, setFlow] = useState<AuthFlow>("signIn");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [shaking, setShaking] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting) return;
    const formData = new FormData(event.currentTarget);
    setError(null);
    setSubmitting(true);
    try {
      await signIn("password", formData);
    } catch (err) {
      setError(mapAuthError(err, flow));
      setShaking(true);
      setSubmitting(false);
    }
    // On success the Authenticated gate swaps screens; no state to reset.
  }

  return (
    <div className="auth">
      <form
        className="auth-card"
        data-shake={shaking ? "true" : undefined}
        onAnimationEnd={() => setShaking(false)}
        onSubmit={handleSubmit}
      >
        <span className="auth-brand">Euno</span>
        <p className="auth-tagline">Find your way back to the people you meet.</p>
        <input
          className="field"
          name="email"
          placeholder="Email"
          type="email"
          inputMode="email"
          autoComplete="email"
          autoCapitalize="none"
          spellCheck={false}
          required
        />
        <input
          className="field"
          name="password"
          placeholder="Password"
          type="password"
          autoComplete={flow === "signIn" ? "current-password" : "new-password"}
          minLength={flow === "signUp" ? 8 : undefined}
          required
        />
        <input name="flow" type="hidden" value={flow} />
        {error !== null && (
          <p className="auth-error" role="alert">
            {error}
          </p>
        )}
        <button className="btn-primary auth-submit" type="submit" disabled={submitting}>
          {submitting && <span className="spinner" aria-hidden="true" />}
          {flow === "signIn" ? "Sign in" : "Create account"}
        </button>
        <button
          className="btn-ghost auth-toggle"
          type="button"
          onClick={() => {
            setFlow(flow === "signIn" ? "signUp" : "signIn");
            setError(null);
          }}
        >
          {flow === "signIn"
            ? "New here? Create an account"
            : "Already have an account? Sign in"}
        </button>
      </form>
    </div>
  );
}

type Selected = { id: Id<"people">; initial: PersonSnapshot | null };

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
  const { signOut } = useAuthActions();
  const [selected, setSelected] = useState<Selected | null>(null);
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
    withScreenTransition(() => setSelected({ id: person._id, initial: person }));
  }

  function close(saved: boolean) {
    withScreenTransition(
      () => {
        setSelected(null);
        if (saved) setQuery("");
      },
      () => setMorphId(null),
    );
  }

  return (
    <>
      <div ref={sentinelRef} className="scroll-sentinel" aria-hidden="true" />
      <header className="app-header" data-scrolled={scrolled ? "true" : "false"}>
        <div className="header-inner">
          {selected === null ? (
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
        {selected === null ? (
          <div className="screen" key="search">
            <SearchAdd
              query={query}
              onQueryChange={setQuery}
              onOpen={open}
              morphId={morphId}
            />
          </div>
        ) : (
          <div className="screen" key={selected.id}>
            <PersonDetail
              id={selected.id}
              initial={selected.initial}
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
