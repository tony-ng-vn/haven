import { useEffect, useRef, useState, type FormEvent } from "react";
import { useMutation } from "convex/react";
import { ConvexError } from "convex/values";
import { api } from "../convex/_generated/api";
import { isValidEmail } from "./lib";

// The public /#/join waitlist. One page that becomes two: a wide viewport gets
// the "constellation" layout (copy settled in the lower third), a narrow one
// gets the "drift" layout (headline up top, capture at the bottom). Both ride
// the same drifting star field. The 620px breakpoint drives layout and copy
// together so they never disagree.
type Mode = "desktop" | "phone";
type Status = "idle" | "submitting" | "joined";

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
    sub: "Every person you meet becomes a point of light - and Euno keeps them from drifting away.",
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
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [mode, setMode] = useState<Mode>(initialMode);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
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

  // The drifting star field. Lives for the component's lifetime and tears
  // down its animation frame on unmount; a still frame under reduced motion.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (canvas === null) return;
    return startDrift(canvas);
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
      await join({ name: name.trim(), email, source: mode });
      setStatus("joined");
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
      <canvas ref={canvasRef} className="wl-sky" aria-hidden="true" />
      <div className="wl-content">
        {status === "joined" ? (
          <div className="wl-joined" role="status">
            <div className="wl-check" aria-hidden="true">
              <CheckIcon />
            </div>
            <p className="wl-checkline">You are on the list.</p>
            <p className="wl-sub wl-joined-sub">
              Thank you for joining us, to be in the true social that brings you to other people in your life
            </p>
          </div>
        ) : (
          <>
            <div className="wl-top">
              <span className="wl-eyebrow">Euno - private beta</span>
              <h1 className="wl-headline">{copy.headline}</h1>
            </div>
            <div className="wl-bottom">
              <p className="wl-sub">{copy.sub}</p>
              <form className="wl-form" onSubmit={onSubmit} noValidate>
                <input
                  className="wl-field"
                  type="text"
                  autoComplete="name"
                  placeholder="Your name"
                  aria-label="Your name"
                  value={name}
                  onChange={(event) => {
                    setName(event.target.value);
                    if (error !== null) setError(null);
                  }}
                />
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

type Star = {
  x: number;
  y: number;
  size: number;
  base: number;
  sp: number;
  tw: number;
  hot: boolean;
};

// A layered parallax field drifting rightward -- deeper (bigger, brighter)
// stars move faster. Returns its own teardown. Ported from the approved
// prototype so the shipped page matches it exactly.
function startDrift(canvas: HTMLCanvasElement): () => void {
  const ctx = canvas.getContext("2d");
  if (ctx === null) return () => {};
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let w = 0;
  let h = 0;
  let raf = 0;
  let stars: Star[] = [];

  function size() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = canvas.clientWidth;
    h = canvas.clientHeight;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function build() {
    size();
    const count = Math.min(300, Math.floor((w * h) / 3600));
    stars = [];
    for (let i = 0; i < count; i++) {
      const depth = Math.random();
      stars.push({
        x: Math.random() * w,
        y: Math.random() * h,
        size: 0.5 + depth * 1.6,
        base: 0.1 + depth * 0.45,
        sp: 0.05 + depth * 0.22,
        tw: Math.random() * 6.28,
        hot: Math.random() < 0.04,
      });
    }
  }

  function frame(t: number) {
    const time = t / 1000;
    ctx!.clearRect(0, 0, w, h);
    for (const s of stars) {
      if (!reduce) {
        s.x += s.sp;
        if (s.x > w + 2) s.x = -2;
      }
      const tw = reduce ? 1 : 0.7 + 0.3 * Math.sin(time * 1.3 + s.tw);
      ctx!.beginPath();
      ctx!.arc(s.x, s.y, s.size, 0, 6.2832);
      if (s.hot) {
        ctx!.fillStyle = `rgba(10,132,255,${s.base + 0.2})`;
        ctx!.shadowColor = "rgba(10,132,255,.8)";
        ctx!.shadowBlur = 6;
      } else {
        ctx!.fillStyle = `rgba(255,255,255,${s.base * tw})`;
        ctx!.shadowBlur = 0;
      }
      ctx!.fill();
    }
    ctx!.shadowBlur = 0;
    if (!reduce) raf = requestAnimationFrame(frame);
  }

  function onResize() {
    build();
    if (reduce) frame(0);
  }

  build();
  if (reduce) frame(0);
  else raf = requestAnimationFrame(frame);
  window.addEventListener("resize", onResize);

  return () => {
    cancelAnimationFrame(raf);
    window.removeEventListener("resize", onResize);
  };
}
