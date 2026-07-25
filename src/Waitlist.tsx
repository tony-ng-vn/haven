import { useEffect, useRef, useState, type FormEvent } from "react";
import { useMutation } from "convex/react";
import { ConvexError } from "convex/values";
import { api } from "../convex/_generated/api";
import { isValidEmail } from "./lib";
import { DriftSky } from "./DriftSky";

// The public /#/join waitlist. One page that becomes two: a wide viewport gets
// the "constellation" layout (copy settled in the lower third), a narrow one
// gets the "drift" layout (headline up top, capture at the bottom). Both ride
// the same drifting star field, and this page takes its constellation lens:
// stars near the pointer join up, which is the headline made interactive. The
// 620px breakpoint drives layout and copy together so they never disagree.
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

// Copy shifts with the layout; each side keeps the wording it was designed with.
const COPY: Record<Mode, {
  headline: string;
  sub: string;
  cta: string;
  fine: string;
}> = {
  desktop: {
    headline: "Your people are a constellation.",
    sub: "Every person you meet becomes a point of light - and Haven keeps them from drifting away.",
    cta: "Join",
    fine: "Private beta",
  },
  phone: {
    headline: "The people you meet, never lost again.",
    sub: "A quiet memory layer over the people of your life. Get in early.",
    cta: "Request access",
    fine: "No spam. Invites go out in waves.",
  },
};

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="#0a84ff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
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

  // Layout follows the page width, flipping at the same breakpoint the copy
  // uses so the two stay in step.
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

  const copy = COPY[mode];

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
                ? "You're already on the list."
                : "You are on the list."}
            </p>
            <p className="wl-sub wl-joined-sub">
              {status === "already"
                ? "This email is already registered - no need to sign up again. We'll be in touch."
                : "Thank you for joining us, to be in the true social that brings you to other people in your life"}
            </p>
          </div>
        ) : (
          <>
            <div className="wl-top">
              <span className="wl-eyebrow">Haven - private beta</span>
              <h1 className="wl-headline">{copy.headline}</h1>
            </div>
            <div className="wl-bottom">
              <p className="wl-sub">{copy.sub}</p>
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
                    {status === "submitting" ? "Joining" : copy.cta}
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
                      {status === "submitting" ? "Joining" : copy.cta}
                    </button>
                  </div>
                </div>
              </form>
              {error !== null ? (
                <p className="wl-error" role="alert">{error}</p>
              ) : (
                <p className="wl-fine">{copy.fine}</p>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
