import { useEffect, useRef, useState, type FormEvent } from "react";
import { useMutation } from "convex/react";
import { ConvexError } from "convex/values";
import { api } from "../convex/_generated/api";
import { isValidEmail } from "./lib";
import { DriftSky } from "./DriftSky";
import { WAITLIST_COPY } from "./waitlistCopy";

// The public waitlist. One page, two layouts at 620px: wide gets the centered
// "constellation" composition, narrow gets headline-up / capture-down. Both
// share one voice from waitlistCopy -- mode only flips layout (and the
// analytics source), never wording. Both ride the same drifting star field
// with the constellation lens: stars near the pointer join up.
type Mode = "desktop" | "phone";
// "already" is a first-class outcome, not an error: the person is on the list,
// they just submitted a second time. The server dedups by email and returns it
// so the UI can say so honestly instead of faking a fresh "joined" (which would
// promise a confirmation email that never comes for a repeat).
type Status = "idle" | "submitting" | "joined" | "already";

const BREAKPOINT = 620;

function initialMode(): Mode {
  return typeof window !== "undefined" && window.innerWidth >= BREAKPOINT
    ? "desktop"
    : "phone";
}

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 6 9 17l-5-5" />
    </svg>
  );
}

export function Waitlist() {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const [mode, setMode] = useState<Mode>(initialMode);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  // The email row stays folded until the person engages the name field, so the
  // page opens as one calm line. Once revealed it stays revealed.
  const [revealed, setRevealed] = useState(false);
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);
  const join = useMutation(api.waitlist.joinWaitlist);

  // Layout follows the page width. Copy does not -- see waitlistCopy.ts.
  useEffect(() => {
    const root = rootRef.current;
    if (root === null) return;
    const observer = new ResizeObserver(([entry]) => {
      setMode(entry.contentRect.width >= BREAKPOINT ? "desktop" : "phone");
    });
    observer.observe(root);
    return () => observer.disconnect();
  }, []);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    // Checked in field order (name above email) so the first error shown is
    // the first thing the person needs to fix.
    if (name.trim() === "") {
      setError("Enter your name.");
      return;
    }
    if (!isValidEmail(email)) {
      setError("Enter a valid email address.");
      return;
    }
    setStatus("submitting");
    try {
      // Honor the server's dedup verdict: a repeat email comes back "already"
      // (no new row, no email), so show that instead of a false fresh join.
      const result = await join({ name: name.trim(), email, source: mode });
      setStatus(result.status === "already" ? "already" : "joined");
    } catch (err) {
      setStatus("idle");
      // ConvexError carries our own server message; anything else is a network
      // or unexpected failure the person can just retry.
      setError(
        err instanceof ConvexError && typeof err.data === "string"
          ? err.data
          : "Something went wrong. Please try again.",
      );
    }
  }

  return (
    <div ref={rootRef} className="waitlist" data-mode={mode}>
      <DriftSky className="wl-sky" lens />
      <div className="wl-content">
        {status === "joined" || status === "already" ? (
          <div className="wl-joined" role="status">
            <div className="wl-check" aria-hidden="true">
              <CheckIcon />
            </div>
            <p className="wl-checkline">
              {status === "already"
                ? WAITLIST_COPY.alreadyTitle
                : WAITLIST_COPY.joinedTitle}
            </p>
            <p className="wl-sub wl-joined-sub">
              {status === "already"
                ? WAITLIST_COPY.alreadyBody
                : WAITLIST_COPY.joinedBody}
            </p>
          </div>
        ) : (
          <>
            <div className="wl-top">
              <span className="wl-eyebrow">{WAITLIST_COPY.eyebrow}</span>
              <h1 className="wl-headline">{WAITLIST_COPY.headline}</h1>
            </div>
            <div className="wl-bottom">
              <p className="wl-sub">{WAITLIST_COPY.sub}</p>
              <form
                className={revealed ? "wl-form is-revealed" : "wl-form"}
                onSubmit={onSubmit}
                noValidate
              >
                <div className="wl-name-row">
                  <input
                    className="wl-field"
                    type="text"
                    autoComplete="name"
                    placeholder="Your name"
                    aria-label="Your name"
                    value={name}
                    onFocus={() => setRevealed(true)}
                    onChange={(event) => {
                      setName(event.target.value);
                      setRevealed(true);
                      if (error !== null) setError(null);
                    }}
                  />
                  {/* Join rides alongside the name until the email drops in,
                      then hands off to the email row's button. */}
                  <button
                    className="wl-go wl-go-name"
                    type="submit"
                    disabled={status === "submitting"}
                    inert={revealed}
                  >
                    {status === "submitting" ? WAITLIST_COPY.submitting : WAITLIST_COPY.cta}
                  </button>
                </div>
                <div className="wl-email-wrap" inert={!revealed}>
                  <div className="wl-email-row">
                    <input
                      className="wl-field"
                      type="email"
                      inputMode="email"
                      autoComplete="email"
                      placeholder="Your email"
                      aria-label="Email address"
                      value={email}
                      onChange={(event) => {
                        setEmail(event.target.value);
                        if (error !== null) setError(null);
                      }}
                    />
                    <button className="wl-go" type="submit" disabled={status === "submitting"}>
                      {status === "submitting" ? WAITLIST_COPY.submitting : WAITLIST_COPY.cta}
                    </button>
                  </div>
                </div>
              </form>
              {/* The domain in the fine print lives here, not in the copy
                  deck: it is the one crawlable "inhavens.com" in the body
                  (locked by seo.test.ts), SEO chrome rather than wording a
                  copy pass may touch. */}
              {error !== null ? (
                <p className="wl-error" role="alert">{error}</p>
              ) : (
                <p className="wl-fine">{WAITLIST_COPY.fine} - inhavens.com</p>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
