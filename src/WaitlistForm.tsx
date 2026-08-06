import { useEffect, useState, type FormEvent } from "react";
import { useMutation } from "convex/react";
import { ConvexError } from "convex/values";
import { api } from "../convex/_generated/api";
import { isValidEmail } from "./lib";
import { WAITLIST_COPY } from "./waitlistCopy";

// The join capture itself: a name field, an email field that folds in once the
// name is engaged, and the three honest end states (joined / already / error).
// Extracted from what used to be the whole waitlist page, so the iOS product
// page (IosPage.tsx, at /waitlist) can carry it without duplicating the logic
// -- the page around it owns the pitch (eyebrow, headline, tagline), this owns
// only the ask.
//
// "already" is a first-class outcome, not an error: the person is on the list,
// they just submitted a second time. The server dedups by email and returns it
// so the UI can say so honestly instead of faking a fresh "joined" (which would
// promise a confirmation email that never comes for a repeat).
type Mode = "desktop" | "phone";
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

export function WaitlistForm() {
  const [mode, setMode] = useState<Mode>(initialMode);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  // The email row stays folded until the person engages the name field, so the
  // form opens as one calm line. Once revealed it stays revealed.
  const [revealed, setRevealed] = useState(false);
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState<string | null>(null);
  const join = useMutation(api.waitlist.joinWaitlist);

  // The backend's source field is desktop/phone, not "which page hosted this" --
  // it is a device-width signal, so it tracks the viewport rather than this
  // component's own (now much narrower) column width.
  useEffect(() => {
    function onResize() {
      setMode(window.innerWidth >= BREAKPOINT ? "desktop" : "phone");
    }
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
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

  if (status === "joined" || status === "already") {
    return (
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
    );
  }

  return (
    <>
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
    </>
  );
}
