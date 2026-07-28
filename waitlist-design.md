# Waitlist design

The public landing page at the root of `inhavens.com`, and the constellation lens that is being added to it.

`mvp-design.md` owns the product architecture and the iOS phases.
`phase1-build-plan.md` owns the iOS onboarding build.
This file owns the web waitlist: what ships today, what the lens adds, and why the rejected alternatives were rejected.

## What the waitlist is

The waitlist is the default landing for anyone who is not signed in.
It sits at the clean root URL rather than behind a `#/join` path, so a shared link has nothing ugly in it.
Routing is decided by `resolveView` in `src/lib.ts`; sign-in stays available at `#/sign-in`.

Its only job is to take a name and an email.
Everything else on the page exists to make that feel worth doing.

## The page today

### Two layouts, one voice

The page becomes two layouts at 620px. Wording does not change with the layout.

Desktop, the "constellation" layout: everything centred, copy settled in the lower third.
Phone, the "drift" layout: headline at the top, capture at the bottom.

Both say the same thing, from `src/waitlistCopy.ts`:
Headline "Your people are a constellation.", button "Join", fine print "Private beta".

`Mode` only drives layout CSS (`data-mode`) and the analytics `source` field.
It must never key marketing copy -- that is how "Join" on web and "Request access" on phone once shipped as two products.
`src/waitlistCopy.test.ts` locks the single-voice contract.

### Progressive disclosure on the form

The page opens as one calm line: a name field with the submit button beside it.
The email row folds in only once the person engages the name field, and once revealed it stays revealed.

This is deliberate.
Two empty fields on first paint reads as a form to be filled out.
One field reads as a question to be answered.

### The three outcomes

The form has three honest end states, not two.

Joined: a new row was created.
Already: the server deduped on email, so no row and no confirmation email.
This is a first-class outcome with its own copy, because faking a fresh join would promise a confirmation email that never arrives.

Error: anything else, with the server's own message when it is a `ConvexError` and a plain retry line otherwise.

Validation runs in field order, name before email, so the first error shown is the first thing to fix.

### The sky

`src/DriftSky.tsx` draws a layered parallax star field on canvas.
Deeper stars are bigger, brighter, and drift faster, all rightward.
Roughly 4 percent of stars are "hot" and carry the platform blue with a glow.
Star count is `min(300, floor(w * h / 3600))`.
Reduced motion gets a single still frame and no animation loop.

The same component backs the sign-in landing, so both surfaces ride the identical sky.

### Tokens in use

Ground `#000000`, ink `#f5f5f7`, secondary `#b8b8bd`, muted `#98989d`, accent `#0a84ff`.
System font stack throughout.
Eyebrow at 13px with 0.16em tracking, uppercase.
Sub at 18px, 1.55 line height.
Capture column caps at 460px.

## The constellation lens

The one thing being added, and now shipped.

### What it does

Stars near the pointer connect into a figure.
Outside the lens they are scattered points; inside, they join up.

That is the headline rendered as an interaction.
Without Haven your people are scattered; Haven is the lens that makes the connections visible.
The gesture is the product thesis, not decoration.

The figure is a minimum spanning tree, the same algorithm `spanningTree` already uses in `src/sky.ts` to draw every user's personal constellation.
Using the same math is the point: the marketing page and the product speak one visual language.

### Settled parameters

| Parameter | Value |
| --- | --- |
| Radius | 195px |
| Follow lag | 0.055 per frame toward the pointer |
| Edge softness | 0.85 of the radius |
| Magnification | 1.18 about the lens centre |
| Base sky dimming | none |
| Line: glow pass | `rgba(255,217,160,0.13)` at 3.2px |
| Line: core pass | `rgba(255,230,190,0.7)` at 0.9px |
| Lit star fill | `rgba(255,226,180,a)` capped at 0.95, `a = min(base * 2.6, 0.9)` |
| Lit star glow | `rgba(255,200,130,0.9)`, blur `10 * a` |
| Lit star size | 1.35x the base star |
| Figure membership | stars with `size > 0.95` within `radius / zoom` |
| Driver | pointer, with wander when idle |
| Idle before wander | 2000ms |

### The three rules that make it work

These were each learned by shipping a broken version first.

**Purely additive.**
The sky under the lens is never darkened.
An earlier version dimmed the base stars to make the revealed layer pop, and it read as a hole punched through the page rather than a revelation.
Nothing is ever taken away, only added.

**No boundary.**
There is no rim, no ring, and no clipping circle.
Stars and lines fade individually by distance from the centre, and a line fades by its weaker end so it never stops dead at an invisible edge.
A hard edge made the effect read as a magnifying-glass tool held over the page; without one it reads as a region of attention.

**Heavy lag.**
At 0.055 the lens trails well behind the cursor.
This is what stops it feeling stuck to the pointer, and it is where the name Breath came from.

### Falloff

`falloff(distance)` returns 1 at the centre and 0 at the radius.

```
if distance >= radius: 0
t = (1 - distance / radius) / softness
clamp t to [0, 1]
```

At softness 0.85 the fade begins almost at the centre, which is what makes the edge invisible.

### What happens on a phone

The lens wanders on its own, and a finger can aim it.

Most waitlist traffic arrives from a link shared into a phone, so the driver cannot be cursor-only.
Shipped behavior is "wander when idle" from round 5 (`design/grill-breath-driver.html`): the lens follows the pointer (or a finger held down), and after about two still seconds it detaches and drifts along a slow path of two sines per axis at incommensurate rates, so it never visibly repeats.
With no cursor, a phone is always wandering until a finger presses the page.

Touch is gated on press: only `pointerdown` through `pointerup` drives the lens.
Free-floating touchmoves and a leftover tap position are ignored, so a phone never gets a lens stuck where the last tap landed.
A finger press snaps the lens under the touch and follows with a tighter lag than the desktop trail; the waitlist root uses `touch-action: none` so iOS cannot rubber-band the page and steal the gesture (that pan is what read as "the whole sky moves").
Form fields keep `touch-action: manipulation` so typing still works.

## How this was decided

Five rounds of visual comparison, each one artifact with five live variants and a picker.
The artifacts are kept in `design/` because the rejected options are the reasoning.

| Round | Question | Chosen | File |
| --- | --- | --- | --- |
| 1 | How should a fluid effect meet the page? | Ink, whole page, bold | `design/grill-liquid-waitlist.html` |
| 2 | Which engine, given that appetite? | Lens | `design/grill-effects-waitlist.html` |
| 3 | What does looking through it mean? | Constellation | `design/grill-lens-waitlist.html` |
| 4 | How restrained should it be? | Breath | `design/grill-constellation-lens.html` |
| 5 | What drives it without a cursor? | Cursor only | `design/grill-breath-driver.html` |

### Rejected, and why

**Warping the words.**
Round 1 explored fluid distortion across the whole page.
It is striking and it costs legibility on the one page whose entire job is a form.

**Nebula, rain, particle reveal, ripple.**
Round 2 alternatives.
Particle reveal was the closest thematically, since the copy is literally about points of light, but it needs the page contents captured and so needs a Chrome flag.
Nebula was the only one that worked without the flag and it washed the black sky out even at low opacity.

**Names, warmth, depth, drift.**
Round 3 alternatives for what the lens reveals.
Names is the strongest runner-up and is worth revisiting as a second state.
Depth and drift are pretty but say something the product does not claim.

**A visible rim, and dimming the sky.**
Round 4.
Both make the lens an object on top of the design rather than part of it.

**Always wandering, tap to bloom, centred pulse.**
Round 5 alternatives, kept in the artifact for when the phone question is reopened.

## Canvas UI

Evaluated at `canvasui.dev` on 2026-07-24 and **not adopted**.

It is a web-only WebGL effects library distributed as source files through a shadcn registry.
The components are genuinely good and dependency-free.

Two reasons it does not ship here.

Its effects render HTML into a canvas through the experimental `html-in-canvas` API, which needs `chrome://flags/#canvas-draw-element` locally and a per-domain origin trial token in production.
Most visitors would see the documented fallback rather than the effect.

More decisively, the effects capture DOM, and a `<canvas>` inside the captured subtree cannot be captured.
The star field is a canvas, so a library effect could never have revealed anything in the sky, which is where all the meaning lives.

The lens is therefore hand-built.
That costs roughly 120 lines to maintain and buys full parameter control plus no flag, no origin trial, and no dependency.

Two findings worth keeping if the library is ever revisited: the content element inside the capture must be `position: relative` with an explicit 100 percent box, because an absolutely positioned child has no containing block inside a canvas layout subtree and collapses to nothing.
And `Clouds` takes its colour as `[r, g, b]` in 0 to 1, not a hex string; a string silently falls through its `auto` check and renders garbage.

If a marketing flourish is ever wanted elsewhere, `Glass` and `Particle Reveal` are the two consistent with this visual language.

## How it is built

The lens lives in the star field, not the page.

`src/lens.ts` holds the geometry and the settled numbers, pure and unit tested, because it is the only part with logic: falloff, magnification, figure membership, and how a line takes its alpha.
`src/DriftSky.tsx` does the drawing.
`spanningTree` is exported from `src/sky.ts` and reused rather than reimplemented, so the landing page and a person's own card are drawn by the same function.

`DriftSky` is shared with the sign-in landing, so the lens sits behind an opt-in `lens` prop that defaults to off.
The waitlist opts in; sign-in keeps today's plain sky until that is its own decision.

The pointer is tracked on `window`, not on the canvas.
The canvas sits behind `.wl-content`, which covers the page, so it never sees a pointer event of its own.
Coordinates convert through the canvas rect and stay in CSS pixels, since the context is already scaled by the device pixel ratio.

The lens fades on pointer presence rather than on movement, so a cursor that arrives and holds still still blooms.
Presence ends on either `mouseleave` or window `blur`, because each one alone misses a case: a fast exit off the top of the window can skip the leave event, and switching apps with the cursor still over the page only fires blur.
Miss both and the figure stays lit at its last position forever, on a page whose whole point is that it follows attention.

### Accessibility and performance

Reduced motion gets the still sky and no lens at all, rather than a frozen one, since a motionless lens under a stationary cursor says nothing.
That path draws its one frame synchronously and never schedules another, since the only `requestAnimationFrame` call is guarded by it.

Wander starts on the first frame when the lens is on, so a phone pays for the figure immediately.
Touch only aims while a finger is down; mouse and pen still follow on move.
The spanning tree runs once per frame over the stars inside the radius, which is a small set.

The form and the copy are unaffected: the lens is a canvas layer behind them and never intercepts pointer events.

### How much figure you get

Star count is `min(300, w * h / 3600)`, so past roughly 1400x900 the cap binds and density falls as the window grows while the radius stays fixed.
The formulas predict about 17 stars in the figure at 1090x830 and about 9 at 1800x1170; the 1800-wide window showed 7 to 8, which still reads as a constellation.
Past roughly 2560 CSS pixels wide it would thin out to a handful.
That is now handled, the way this note said to handle it: `lensFigure` falls back to the nearest qualifying stars when fewer than seven fall inside the radius, and hands back the radius the fade should use so the stars it reached for are not lit with edges drawn at zero alpha.
The star cap and the brightness threshold are untouched, because both of those change the sky on every screen rather than the figure on the few that need it.

## Open items

Whether the sign-in landing should get the lens too.
It is one prop away; deliberately left off for now.

The phone case now ships "wander when idle" with press-gated touch aiming.
Tap-to-bloom and centred pulse remain in `design/grill-breath-driver.html` if the driver needs another pass.

The rename pass is still outstanding across copy, emails, and meta, tracked in `mvp-design.md`.

Whether "Names" returns as a second state of the lens once the product has real contacts to name.
