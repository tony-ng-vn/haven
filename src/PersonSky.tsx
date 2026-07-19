import { memo, useId, useMemo, type CSSProperties } from "react";
import { buildSky, type SkyStar } from "./sky";

// The non-featured minors are dealt round-robin into this many group-shimmer
// layers. Star positions are random with respect to index, so each layer is an
// even spatial sample and the field breathes as one, not per node.
const SHIMMER_LAYERS = 3;

// A person's unique patch of deep space, rendered from their seeded sky
// data. Purely presentational; all randomness lives in buildSky. Memoized
// because it renders ~190 SVG nodes and would otherwise redo that work on
// every drag frame of the parent triage card.
export const PersonSky = memo(function PersonSky({
  name,
  handle,
}: {
  name: string;
  handle?: string;
}) {
  const sky = useMemo(() => buildSky(name, handle), [name, handle]);
  const uid = useId();
  const haloId = `halo-${uid}`;

  const twinkle = (dur: number, delay: number, hi: number, lo: number, rvd?: number) =>
    ({
      "--d": `${dur.toFixed(1)}s`,
      "--dl": `${delay.toFixed(1)}s`,
      "--hi": hi.toFixed(2),
      "--lo": lo.toFixed(2),
      ...(rvd !== undefined ? { "--rvd": rvd.toFixed(3) } : {}),
    }) as CSSProperties;

  // A static minor sits at the twinkle midpoint -- the time-average brightness
  // of an alive star -- so the field reads exactly as dense as before. It still
  // carries --rvd so the one-shot Ignition reveal staggers it in like the rest.
  const dim = (hi: number, lo: number, rvd: number) =>
    ({
      "--mid": ((hi + lo) / 2).toFixed(2),
      "--rvd": rvd.toFixed(3),
    }) as CSSProperties;

  // Split minors once: the seeded featured few keep their own twinkle; the rest
  // are dealt into the shimmer layers.
  const featuredMinors: Array<{ s: SkyStar; i: number }> = [];
  const shimmerLayers: Array<Array<{ s: SkyStar; i: number }>> = Array.from(
    { length: SHIMMER_LAYERS },
    () => [],
  );
  sky.minors.forEach((s, i) => {
    if (s.featured) featuredMinors.push({ s, i });
    else shimmerLayers[i % SHIMMER_LAYERS].push({ s, i });
  });

  return (
    <svg
      className="sky-svg"
      viewBox={`0 0 ${sky.width} ${sky.height}`}
      preserveAspectRatio="xMidYMid slice"
      aria-hidden="true"
    >
      <defs>
        <radialGradient id={haloId}>
          <stop offset="0%" stopColor="rgba(255,255,255,0.9)" />
          <stop offset="45%" stopColor="rgba(255,255,255,0.25)" />
          <stop offset="100%" stopColor="rgba(255,255,255,0)" />
        </radialGradient>
        {sky.nebulae.map((n, i) => (
          <radialGradient key={i} id={`neb-${uid}-${i}`}>
            <stop offset="0%" stopColor={`hsla(${n.hue}, 82%, 58%, ${n.alpha})`} />
            <stop offset="100%" stopColor={`hsla(${n.hue}, 82%, 58%, 0)`} />
          </radialGradient>
        ))}
      </defs>

      {sky.nebulae.map((n, i) => (
        <ellipse
          key={`n${i}`}
          className="sky-neb"
          cx={n.cx}
          cy={n.cy}
          rx={n.rx}
          ry={n.ry}
          fill={`url(#neb-${uid}-${i})`}
        />
      ))}

      {/* The alive minors: each keeps its own twinkle, exactly as before. */}
      {featuredMinors.map(({ s, i }) => (
        <circle
          key={`m${i}`}
          className="sky-tw sky-minor"
          style={twinkle(s.dur, s.delay, s.hi, s.lo, s.rvd)}
          cx={s.x.toFixed(1)}
          cy={s.y.toFixed(1)}
          r={s.r.toFixed(2)}
          fill="#fff"
        />
      ))}

      {/* The rest: static at their midpoint, breathing together under a few
          slow group-shimmer layers instead of ~130 per-node timelines. */}
      {shimmerLayers.map((layer, l) => (
        <g key={`sh${l}`} className={`sky-shimmer sky-shimmer-${l}`}>
          {layer.map(({ s, i }) => (
            <circle
              key={`d${i}`}
              className="sky-dim"
              style={dim(s.hi, s.lo, s.rvd)}
              cx={s.x.toFixed(1)}
              cy={s.y.toFixed(1)}
              r={s.r.toFixed(2)}
              fill="#fff"
            />
          ))}
        </g>
      ))}

      {sky.giants.map((g, i) => (
        <circle
          key={`g${i}`}
          className="sky-tw sky-minor"
          style={twinkle(g.dur, g.delay, g.hi, g.lo, g.rvd)}
          cx={g.x.toFixed(1)}
          cy={g.y.toFixed(1)}
          r={g.r.toFixed(2)}
          fill={`hsla(${g.hue}, 80%, 75%, 1)`}
        />
      ))}

      {sky.edges.map(([a, b], i) => (
        <line
          key={`e${i}`}
          className="sky-cline"
          style={{ "--ei": i } as CSSProperties}
          pathLength={1}
          x1={sky.majors[a].x.toFixed(1)}
          y1={sky.majors[a].y.toFixed(1)}
          x2={sky.majors[b].x.toFixed(1)}
          y2={sky.majors[b].y.toFixed(1)}
          stroke="rgba(255,255,255,0.16)"
          strokeWidth="0.8"
        />
      ))}

      {sky.majors.map((s, i) => (
        <g
          key={`M${i}`}
          className="sky-tw sky-majorg"
          style={{ ...twinkle(s.dur, s.delay, s.hi, s.lo), "--mi": i } as CSSProperties}
        >
          <circle
            cx={s.x.toFixed(1)}
            cy={s.y.toFixed(1)}
            r={(s.r * 6).toFixed(1)}
            fill={`url(#${haloId})`}
            opacity="0.5"
          />
          <circle
            cx={s.x.toFixed(1)}
            cy={s.y.toFixed(1)}
            r={s.r.toFixed(2)}
            fill={`hsla(${s.hue}, 60%, 88%, 1)`}
          />
        </g>
      ))}

      {sky.flares.map((f, i) => (
        <g
          key={`f${i}`}
          className="sky-flare sky-flareg"
          style={{ "--d": `${f.dur.toFixed(1)}s`, "--dl": `${f.delay.toFixed(1)}s` } as CSSProperties}
        >
          <path
            d={`M ${f.x} ${f.y - f.len} L ${f.x + 1.1} ${f.y} L ${f.x} ${f.y + f.len} L ${f.x - 1.1} ${f.y} Z`}
            fill="rgba(255,255,255,0.5)"
          />
          <path
            d={`M ${f.x - f.len} ${f.y} L ${f.x} ${f.y + 1.1} L ${f.x + f.len} ${f.y} L ${f.x} ${f.y - 1.1} Z`}
            fill="rgba(255,255,255,0.4)"
          />
        </g>
      ))}

      <line
        className="sky-shoot"
        style={{ "--sdl": `${sky.shoot.delay.toFixed(1)}s` } as CSSProperties}
        x1={sky.shoot.x1.toFixed(1)}
        y1={sky.shoot.y1.toFixed(1)}
        x2={sky.shoot.x2.toFixed(1)}
        y2={sky.shoot.y2.toFixed(1)}
        stroke="rgba(255,255,255,0.85)"
        strokeWidth="1.6"
        strokeLinecap="round"
      />
    </svg>
  );
});
