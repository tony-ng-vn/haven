import { useEffect, useRef } from "react";

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

// The drifting star field as a self-contained background layer. Runs for the
// host's lifetime and tears down its animation frame on unmount; a single still
// frame under reduced motion. Shared by the waitlist and the sign-in landing so
// both ride the exact same sky.
export function DriftSky({ className }: { className?: string }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = canvasRef.current;
    if (canvas === null) return;
    return startDrift(canvas);
  }, []);
  return <canvas ref={canvasRef} className={className} aria-hidden="true" />;
}
