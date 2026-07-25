import { useEffect, useRef } from "react";
import { LENS, edgeAlpha, falloff, figureStars, magnify } from "./lens";
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

// A layered parallax field drifting rightward -- deeper (bigger, brighter)
// stars move faster. Returns its own teardown. Ported from the approved
// prototype so the shipped page matches it exactly.
//
// With `withLens`, stars near the pointer also join into a constellation. The
// figure is additive: the sky underneath is never dimmed and the lens has no
// rim, so it reads as a region of attention rather than a hole in the page.
function startDrift(canvas: HTMLCanvasElement, withLens: boolean): () => void {
  const ctx = canvas.getContext("2d");
  if (ctx === null) return () => {};
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  // A lens that cannot follow says nothing, so reduced motion gets the still
  // sky and no lens at all rather than a frozen one.
  const lensOn = withLens && !reduce;
  let w = 0;
  let h = 0;
  let raf = 0;
  let stars: Star[] = [];

  // Where the lens is, where it is heading, and how far it has faded in. It
  // starts off-canvas so nothing is drawn until the pointer first moves.
  const lens = { x: -1, y: -1, tx: -1, ty: -1, on: 0 };
  let hasPointer = false;

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
      ctx!.fillStyle = `rgba(10,132,255,${s.base + 0.2})`;
      ctx!.shadowColor = "rgba(10,132,255,.8)";
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
    const inside = figureStars(stars, centre);
    if (inside.length === 0) return;
    // The same minimum spanning tree that draws a person's own constellation,
    // so the landing page and the product speak one visual language.
    const points = inside.map((s) => magnify(s, centre));

    for (const [a, b] of spanningTree(points)) {
      const f = edgeAlpha(points[a], points[b], centre) * lens.on;
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
      const f = falloff(Math.hypot(p.x - centre.x, p.y - centre.y)) * lens.on;
      if (f <= 0.01) return;
      drawLit(p, s, Math.min(s.base * 2.6, 0.9) * f, time);
    });
  }

  function frame(t: number) {
    const time = t / 1000;
    ctx!.clearRect(0, 0, w, h);

    if (lensOn) {
      // Fade on presence, not on movement: a cursor that arrives and holds
      // still should still bloom, and one that leaves should fade out slowly.
      if (hasPointer) lens.on = Math.min(lens.on + 0.05, 1);
      else lens.on = Math.max(lens.on - 0.02, 0);
      // Heavy lag: the lens trails well behind the cursor, which is what stops
      // it feeling attached to the pointer.
      lens.x += (lens.tx - lens.x) * LENS.lag;
      lens.y += (lens.ty - lens.y) * LENS.lag;
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
    // A touch must never masquerade as a cursor, or a phone would get a lens
    // that teleports to wherever the last tap landed.
    if (event.pointerType === "touch") return;
    const rect = canvas.getBoundingClientRect();
    lens.tx = event.clientX - rect.left;
    lens.ty = event.clientY - rect.top;
    // First sighting: place the lens rather than flying it in from the corner.
    if (lens.x < 0) {
      lens.x = lens.tx;
      lens.y = lens.ty;
    }
    hasPointer = true;
  }

  function onPointerLeave() {
    hasPointer = false;
  }

  build();
  if (reduce) frame(0);
  else raf = requestAnimationFrame(frame);
  window.addEventListener("resize", onResize);
  if (lensOn) {
    window.addEventListener("pointermove", onPointerMove);
    document.documentElement.addEventListener("pointerleave", onPointerLeave);
  }

  return () => {
    cancelAnimationFrame(raf);
    window.removeEventListener("resize", onResize);
    window.removeEventListener("pointermove", onPointerMove);
    document.documentElement.removeEventListener("pointerleave", onPointerLeave);
  };
}

// The drifting star field as a self-contained background layer. Runs for the
// host's lifetime and tears down its animation frame on unmount; a single still
// frame under reduced motion. Shared by the waitlist and the sign-in landing so
// both ride the exact same sky.
//
// The constellation lens is opt-in: the waitlist takes it, the sign-in landing
// keeps the plain sky.
export function DriftSky({
  className,
  lens = false,
}: {
  className?: string;
  lens?: boolean;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    if (canvas === null) return;
    return startDrift(canvas, lens);
  }, [lens]);
  return <canvas ref={canvasRef} className={className} aria-hidden="true" />;
}
