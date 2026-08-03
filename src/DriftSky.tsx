import { useEffect, useRef } from "react";
import {
  LENS,
  edgeAlpha,
  falloff,
  gestureEnabled,
  lensFigure,
  isTouchPointer,
  magnify,
  wanderPoint,
} from "./lens";
import { spanningTree } from "./sky";

type Star = {
  x: number;
  y: number;
  size: number;
  base: number;
  sp: number;
  tw: number;
  hot: boolean;
};

function isFormTarget(target: EventTarget | null): boolean {
  if (!(target instanceof Element)) return false;
  return target.closest("input, textarea, button, select, label, a") !== null;
}

// A layered parallax field drifting rightward -- deeper (bigger, brighter)
// stars move faster. Returns its own teardown. Ported from the approved
// prototype so the shipped page matches it exactly.
//
// With `withLens`, stars near the pointer join into a constellation. The
// figure is additive: the sky underneath is never dimmed and the lens has no
// rim, so it reads as a region of attention rather than a hole in the page.
// When the pointer is gone or still for a couple of seconds the lens wanders
// on its own, which is what a phone sees (and what keeps an idle desktop
// alive) -- this wander is on whenever the lens is, `interactive` or not.
// `interactive` gates only the pointer/touch listeners on top of that: a
// finger down on the page snaps the lens under it and follows tightly for
// the press, lifting returns to wander -- but that costs a non-passive
// touchmove listener that blocks page scroll under a drag, which only a
// fixed, nothing-to-scroll surface can afford. See gestureEnabled in lens.ts.
function startDrift(
  canvas: HTMLCanvasElement,
  withLens: boolean,
  interactive: boolean,
): () => void {
  const ctx = canvas.getContext("2d");
  if (ctx === null) return () => {};
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  // A lens that cannot follow says nothing, so reduced motion gets the still
  // sky and no lens at all rather than a frozen one.
  const lensOn = withLens && !reduce;
  const gestureOn = gestureEnabled({ lensOn, interactive });
  let w = 0;
  let h = 0;
  let raf = 0;
  let stars: Star[] = [];

  // Where the lens is, where it is heading, and how far it has faded in. It
  // starts off-canvas so nothing is drawn until the first drive (pointer or
  // wander) places it.
  const lens = { x: -1, y: -1, tx: -1, ty: -1, on: 0 };
  let hasPointer = false;
  // Touch only counts while a finger is down. Free-floating touchmoves and a
  // leftover tap position must not stick a lens the way a hovering cursor can.
  let touchActive = false;
  let lastMove = -1e9;

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

  function drawStar(s: Star, time: number) {
    const tw = reduce ? 1 : 0.7 + 0.3 * Math.sin(time * 1.3 + s.tw);
    ctx!.beginPath();
    ctx!.arc(s.x, s.y, s.size, 0, 6.2832);
    if (s.hot) {
      // Star amber, the accent from HavenColor -- a lit star is this colour.
      ctx!.fillStyle = `rgba(255,217,160,${s.base + 0.2})`;
      ctx!.shadowColor = "rgba(255,217,160,.8)";
      ctx!.shadowBlur = 6;
    } else {
      ctx!.fillStyle = `rgba(255,255,255,${s.base * tw})`;
      ctx!.shadowBlur = 0;
    }
    ctx!.fill();
  }

  // A star inside the lens, re-lit warm on top of the white one already drawn.
  function drawLit(p: { x: number; y: number }, s: Star, alpha: number, time: number) {
    const tw = reduce ? 1 : 0.75 + 0.25 * Math.sin(time * 1.3 + s.tw);
    ctx!.beginPath();
    ctx!.arc(p.x, p.y, s.size * 1.35, 0, 6.2832);
    ctx!.fillStyle = `rgba(255,226,180,${Math.min(alpha * tw, 0.95)})`;
    ctx!.shadowColor = "rgba(255,200,130,.9)";
    ctx!.shadowBlur = 10 * alpha;
    ctx!.fill();
    ctx!.shadowBlur = 0;
  }

  function drawFigure(time: number) {
    const centre = { x: lens.x, y: lens.y };
    // The radius comes back from here rather than being LENS.radius: on a wide
    // window the star cap makes the sky sparse, and the lens reaches out to
    // find a figure instead of showing two stars and a line.
    const { stars: inside, radius } = lensFigure(stars, centre);
    if (inside.length === 0) return;
    // The same minimum spanning tree that draws a person's own constellation,
    // so the landing page and the product speak one visual language.
    const points = inside.map((s) => magnify(s, centre));

    for (const [a, b] of spanningTree(points)) {
      const f = edgeAlpha(points[a], points[b], centre, radius) * lens.on;
      if (f <= 0.01) continue;
      // Two passes: a wide soft glow, then a hairline core on top of it.
      ctx!.strokeStyle = `rgba(255,217,160,${0.13 * f})`;
      ctx!.lineWidth = 3.2;
      ctx!.beginPath();
      ctx!.moveTo(points[a].x, points[a].y);
      ctx!.lineTo(points[b].x, points[b].y);
      ctx!.stroke();
      ctx!.strokeStyle = `rgba(255,230,190,${0.7 * f})`;
      ctx!.lineWidth = 0.9;
      ctx!.beginPath();
      ctx!.moveTo(points[a].x, points[a].y);
      ctx!.lineTo(points[b].x, points[b].y);
      ctx!.stroke();
    }

    inside.forEach((s, i) => {
      const p = points[i];
      const f = falloff(Math.hypot(p.x - centre.x, p.y - centre.y), radius) * lens.on;
      if (f <= 0.01) return;
      drawLit(p, s, Math.min(s.base * 2.6, 0.9) * f, time);
    });
  }

  function placeLens(x: number, y: number, snap: boolean) {
    lens.tx = x;
    lens.ty = y;
    // First sighting, or a fresh finger press: place rather than flying in.
    if (snap || lens.x < 0) {
      lens.x = lens.tx;
      lens.y = lens.ty;
    }
  }

  function aimFromClient(clientX: number, clientY: number, now: number, snap: boolean) {
    const rect = canvas.getBoundingClientRect();
    placeLens(clientX - rect.left, clientY - rect.top, snap);
    hasPointer = true;
    lastMove = now;
  }

  function frame(t: number) {
    const time = t / 1000;
    ctx!.clearRect(0, 0, w, h);

    if (lensOn) {
      // Follow while the pointer (or a finger) is active and recent; otherwise
      // wander so a phone always sees the figure and an idle desktop stays alive.
      const wandering = !hasPointer || t - lastMove > LENS.idleMs;
      if (wandering) {
        const p = wanderPoint(time, w, h);
        placeLens(p.x, p.y, false);
        lens.on = Math.min(lens.on + 0.012, 1);
      } else {
        // Fade on presence, not on movement: a cursor that arrives and holds
        // still should still bloom.
        lens.on = Math.min(lens.on + 0.05, 1);
      }
      // Desktop trails; a finger needs a tighter chase or the figure never
      // seems to answer the touch.
      const lag = touchActive ? LENS.touchLag : LENS.lag;
      lens.x += (lens.tx - lens.x) * lag;
      lens.y += (lens.ty - lens.y) * lag;
    }

    for (const s of stars) {
      if (!reduce) {
        s.x += s.sp;
        if (s.x > w + 2) s.x = -2;
      }
      drawStar(s, time);
    }
    ctx!.shadowBlur = 0;

    if (lensOn && lens.on > 0.01) drawFigure(time);
    ctx!.shadowBlur = 0;

    if (!reduce) raf = requestAnimationFrame(frame);
  }

  function onResize() {
    build();
    if (reduce) frame(0);
  }

  // The canvas sits behind the page content, so the pointer is tracked on the
  // window and converted to canvas coordinates. The context is already scaled
  // by the device pixel ratio, so these stay CSS pixels.
  function onPointerMove(event: PointerEvent) {
    if (isTouchPointer(event.pointerType) && !touchActive) return;
    aimFromClient(event.clientX, event.clientY, performance.now(), false);
  }

  function onPointerDown(event: PointerEvent) {
    if (!isTouchPointer(event.pointerType)) return;
    touchActive = true;
    // Snap under the finger and bloom immediately -- lag-from-afar is why a
    // phone felt like "nothing moves" while the sky kept drifting.
    aimFromClient(event.clientX, event.clientY, performance.now(), true);
    lens.on = Math.max(lens.on, 0.7);
  }

  function onPointerUp(event: PointerEvent) {
    if (!isTouchPointer(event.pointerType)) return;
    touchActive = false;
    hasPointer = false;
  }

  // Stop iOS from rubber-banding / panning the page under a drag. That pan is
  // what read as "the whole sky moves" when the lens was not following.
  // Form controls keep their native behavior.
  function onTouchMove(event: TouchEvent) {
    if (!touchActive) return;
    if (isFormTarget(event.target)) return;
    if (event.cancelable) event.preventDefault();
    const touch = event.touches[0];
    if (touch === undefined) return;
    aimFromClient(touch.clientX, touch.clientY, performance.now(), false);
  }

  // Two ways to notice the cursor is gone, because either one alone misses
  // cases: a fast exit off the top of the window can skip the leave event, and
  // switching apps with the pointer still over the page only fires blur. Miss
  // both and the figure would stay locked to the last position forever (wander
  // would still cover idle, but blur should release the follow target).
  function onPointerGone() {
    hasPointer = false;
    touchActive = false;
  }

  build();
  if (reduce) frame(0);
  else raf = requestAnimationFrame(frame);
  window.addEventListener("resize", onResize);
  if (gestureOn) {
    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerdown", onPointerDown);
    window.addEventListener("pointerup", onPointerUp);
    window.addEventListener("pointercancel", onPointerUp);
    // Non-passive: we must preventDefault on sky drags so Safari cannot pan.
    window.addEventListener("touchmove", onTouchMove, { passive: false });
    document.addEventListener("mouseleave", onPointerGone);
    window.addEventListener("blur", onPointerGone);
  }

  return () => {
    cancelAnimationFrame(raf);
    window.removeEventListener("resize", onResize);
    window.removeEventListener("pointermove", onPointerMove);
    window.removeEventListener("pointerdown", onPointerDown);
    window.removeEventListener("pointerup", onPointerUp);
    window.removeEventListener("pointercancel", onPointerUp);
    window.removeEventListener("touchmove", onTouchMove);
    document.removeEventListener("mouseleave", onPointerGone);
    window.removeEventListener("blur", onPointerGone);
  };
}

// The drifting star field as a self-contained background layer. Runs for the
// host's lifetime and tears down its animation frame on unmount; a single still
// frame under reduced motion. Shared across every public page so they all ride
// the exact same sky.
//
// The constellation lens is opt-in (`lens`): most callers keep the plain sky.
// `interactive` narrows it further -- it only matters when `lens` is on, and
// defaults to true so an existing `lens` caller keeps today's behavior
// unchanged. The landing hero is the one caller that pulls them apart: lens
// on for every device (the figure and its wander), interactive only for a
// fine pointer (see gestureEnabled in lens.ts for why).
export function DriftSky({
  className,
  lens = false,
  interactive = true,
}: {
  className?: string;
  lens?: boolean;
  interactive?: boolean;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    if (canvas === null) return;
    return startDrift(canvas, lens, interactive);
  }, [lens, interactive]);
  return <canvas ref={canvasRef} className={className} aria-hidden="true" />;
}
