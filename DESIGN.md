---
name: Euno
description: A quiet, content-first memory layer that hands you back the people you have met.
colors:
  signal-blue: "#0071e3"
  signal-blue-dark: "#0a84ff"
  signal-blue-text: "#0069d5"
  quiet-red: "#d70015"
  quiet-red-dark: "#ff453a"
  ink: "#1d1d1f"
  ink-dark: "#f5f5f7"
  muted: "#6e6e73"
  muted-dark: "#98989d"
  surface: "#ffffff"
  surface-dark: "#1c1c1e"
  canvas: "#f5f5f7"
  canvas-dark: "#000000"
  hairline: "#00000014"
  hairline-dark: "#ffffff1a"
typography:
  display:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif"
    fontSize: "28px"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.02em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "normal"
rounded:
  md: "16px"
  lg: "24px"
  pill: "980px"
spacing:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "24px"
  xxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.signal-blue}"
    textColor: "#ffffff"
    rounded: "{rounded.pill}"
    padding: "12px 20px"
    typography: "{typography.body}"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.signal-blue-text}"
    rounded: "{rounded.pill}"
    padding: "8px 12px"
    typography: "{typography.body}"
  input-field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "14px 16px"
    typography: "{typography.body}"
  result-row:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "14px 16px"
    typography: "{typography.body}"
  card-auth:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "32px 28px"
---

# Design System: Euno

Scope: this covers the legacy web surface only, under the app's old name.
The native iOS client has its own visual language, a dark dusk palette with serif reserved for people's names, defined in `phase1-build-plan.md` under Design tokens.
Do not apply the tokens below to anything in `ios/`.

## 1. Overview

**Creative North Star: "The Quiet Room"**

Euno is a calm, private space where a person is gently handed back to you. The whole visual
system exists to get out of the way: the search box and the person are the heroes, and every
other pixel steps back so they can lead. Depth is soft, color is rare, and motion only ever
confirms that something happened. Nothing here performs, competes for attention, or asks the
user to stop and figure it out.

The palette is drawn from Apple's platform conventions on purpose. Familiarity is the feature:
a person opening Euno should feel like they already know how it works. The system stack, the
16px rounded surfaces, the single blue reserved for the one action worth taking -- these are
trustworthy defaults, not brand flair. The design earns quiet by leaning on what people already
recognize, then removing everything else.

The Quiet Room explicitly rejects two neighbors. It is not a social network: no feeds, follower
counts, activity streams, or engagement mechanics. It is not a CRM: no pipelines, stages, scores,
or dashboards of metrics. These are relationships, not leads, and Euno never grades how well you
know someone. The interface should always feel like a private room, never a stage and never a
sales floor.

**Key Characteristics:**
- Content-first: one primary action per screen, chrome recedes.
- Familiar by design: the system font stack and platform-native blue.
- Flat surfaces, soft lift: hairline borders at rest, gentle shadow only when something floats.
- Rare accent: a single blue, spent only on the primary action, focus, and selection.
- Calm motion: 140-280ms confirmations on a strong ease-out; the only element that ever
  travels between screens is the tapped name.
- Light and dark as equals, following the system preference.

## 2. Colors

A near-monochrome system where a single blue is the only saturated voice, and everything else is
a quiet ramp of neutral ink on soft surfaces.

### Primary
- **Signal Blue** (#0071e3 light / #0a84ff dark): The only accent in the system, named for its
  job -- it signals the one action worth taking. Used on primary buttons, the focus glow ring,
  and the current selection. Never used for decoration, dividers, or backgrounds.
- **Signal Blue, text grade** (#0069d5 light / #0a84ff dark): The tinted-text variant for ghost
  buttons and inline links. The light value sits one step deeper than the fill so 17px text
  holds 4.8:1 on the canvas. Filled buttons keep #0071e3 in both modes, so white labels hold
  4.7:1 everywhere.

### State
- **Quiet Red** (#d70015 light / #ff453a dark): Error text only -- a failed sign-in, a failed
  save. Both values hold 4.9:1 or better on their surfaces. Never a fill, never decorative.

### Neutral
- **Ink** (#1d1d1f light / #f5f5f7 dark): Primary text. The person's name, the words the user
  typed, everything meant to be read.
- **Muted** (#6e6e73 light / #98989d dark): Secondary text only -- field labels, the sign-in
  tagline, quiet helper copy. Never body text.
- **Surface** (#ffffff light / #1c1c1e dark): The material that inputs, result rows, and cards
  are cut from. It sits one step above the canvas.
- **Canvas** (#f5f5f7 light / #000000 dark): The body background the surfaces rest on.
- **Hairline** (#00000014 light / #ffffff1a dark): The 1px border that defines a surface without
  drawing attention. An 8% (light) / 10% (dark) wash, never a hard line.

### Named Rules
**The One Blue Rule.** Signal Blue is the only saturated color in the product outside the error
state's Quiet Red. If a screen shows blue in two unrelated places, one of them is wrong. Its
rarity is what makes the primary action unmistakable.

**The Muted-Is-Not-Body Rule.** Muted gray (#6e6e73) is for labels and helper text only. Body
text is always Ink. Muted gray running as body copy is the fastest way to make a calm interface
read as washed-out and hard to read.

## 3. Typography

**Display Font:** System stack (-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif)
**Body Font:** Same system stack

**Character:** One family, tuned by size and weight rather than by pairing. On Apple devices this
resolves to SF Pro, which is exactly the point -- the type should feel native and unremarked, so
the words carry the meaning and the letterforms never announce themselves.

### Hierarchy
- **Display** (600, 28px, 1.1 line-height, -0.02em tracking): The person's name on the detail
  screen and the Euno wordmark on sign-in. The largest type in the product; there is no hero
  display scale above it because Euno never shouts.
- **Title** (600, 20px, 1.2, -0.02em): The Euno wordmark in the app header. Quiet brand presence,
  not a banner.
- **Body** (400, 17px, 1.5): Everything the user reads or types -- inputs, result rows, button
  labels, context. The workhorse size. Prose in the context field stays comfortable at 65-75ch.
- **Label** (400, 13px, muted): Field labels ("Link", "Context") and the sign-in tagline. Small,
  quiet, always in Muted gray.

### Named Rules
**The Size-And-Weight Rule.** Hierarchy comes from size and weight, never from boxes, rules, or
color. If a heading needs a border or a background tint to read as important, the size and weight
are wrong.

## 4. Elevation

Flat by default, soft on lift. Surfaces rest flat, defined only by a 1px hairline border. Depth
appears in exactly two situations: when something genuinely floats above the page, and when a
control responds to focus. There is no ambient drop-shadow on ordinary cards and rows; stacking
them with shadows would read as heavier and busier than The Quiet Room allows.

### Shadow Vocabulary
- **Floating panel** (`box-shadow: 0 12px 40px rgba(0,0,0,0.12)`): For a surface that is truly
  lifted off the page -- the sign-in card, and any future modal or sheet. Large, soft, and diffuse,
  never a tight dark drop shadow.
- **Focus glow** (`box-shadow: 0 0 0 4px color-mix(in srgb, var(--accent) 15%, transparent)`):
  A soft Signal Blue ring on the focused input, paired with an accent border. This is feedback,
  not decoration.

### Named Rules
**The Flat-At-Rest Rule.** A surface at rest carries a hairline border and no shadow. Shadow is a
response to state (a panel that floats, a control that has focus), never a default coat of paint.
If it looks like a 2014 app, the shadow is too dark and the blur is too tight.

## 5. Components

### Buttons
- **Shape:** Full pill (980px radius). The one shape that reads as "tap me."
- **Primary:** Signal Blue background, white text, 500 weight, 17px, 12-20px padding. One per
  screen -- Save, Add, Sign in. This is where the product's only accent is spent.
- **Pressed:** A quiet 0.97 scale on :active (140ms, strong ease-out). Hover only deepens the
  fill slightly, and only on real pointers; the press is an acknowledgement, not a bounce.
- **Secondary / Ghost:** For Back, Sign out, and the sign-in mode toggle. Transparent
  background, Signal Blue text grade, pill-shaped hit target with a soft accent tint on hover
  and the same 0.97 press. Reads as an action the way platform text buttons do, without ever
  competing with the one filled pill.

### Inputs / Fields
- **Style:** Surface background, 1px hairline border, 16px radius, 14-16px padding, 17px text.
  Large and forgiving to tap.
- **Focus:** Border shifts to Signal Blue and a soft 4px blue glow ring appears (150ms). The only
  moment an input carries color.
- **Error / Disabled:** Errors render as a 13px Quiet Red line near the control (sign-in, save),
  announced politely to assistive tech. Disabled controls drop to 55% opacity and refuse the
  press scale.
- **Search anatomy:** A muted magnifier sits inside the field, a circular clear button appears
  once there is text, and the input carries 44px side padding so type never collides with
  either.

### Result Rows
- **Style:** A full-width tappable button styled as a Surface row -- hairline border, 16px radius,
  17px Ink text, left-aligned. The list of people the search returns.
- **Pressed:** A barely-there scale to 0.985 on :active (140ms), so the tap registers physically
  without motion drawing the eye. Hover is a 4% ink tint, gated to real pointers.

### Cards / Containers
- **Corner Style:** 24px radius on the sign-in card (larger and softer than the 16px inputs it
  holds); 16px on inline surfaces.
- **Background:** Surface, on the Canvas body.
- **Shadow Strategy:** Floating panel shadow only when the card floats (sign-in). Inline surfaces
  stay flat per the Flat-At-Rest Rule.
- **Border:** 1px hairline.
- **Internal Padding:** Generous -- 32px 28px on the sign-in card. Let the content breathe.

### Header
- **Material:** Sticky and translucent -- 78% canvas over a 20px blur with 180% saturation, so
  content scrolls under it like platform chrome. A hairline appears on its bottom edge only
  once content has actually scrolled beneath it. Reduced transparency gets a solid header.
- **Slots:** The wordmark on the search screen, the chevron Back ghost on the person screen,
  Sign out as a ghost on the right.

### The Name Morph (signature)
The tapped name is the only element that travels between screens: the search row's text glides
into the detail title (280ms, strong ease-in-out) while the rest of the screen quietly
crossfades (180ms out, 220ms in). It is the product thesis rendered as motion -- you bring a
fragment, Euno hands you back the person. Browsers without the View Transitions API get a
260ms rise-and-fade instead; reduced motion gets an instant swap.

### Layout
- **Frame:** A single centered column, max-width 640px, 24px page padding with safe-area
  insets. Euno is a phone-shaped reading width even on desktop; the person is meant to be
  read, not spread across a dashboard.
- **Responsive:** The column simply narrows on small screens. There are no sidebars, panels, or
  breakpoint-driven grids to collapse -- structure this simple does not need them.

## 6. Do's and Don'ts

### Do:
- **Do** spend Signal Blue only on the primary action, focus, and selection. One blue per screen.
- **Do** keep one primary action per screen; let the search box and the person lead.
- **Do** use Ink for anything meant to be read, and reserve Muted (#6e6e73) for labels and helper
  text only.
- **Do** keep surfaces flat with a hairline border at rest; add shadow only when something floats
  or takes focus.
- **Do** hold body text and placeholders at 4.5:1 contrast or better (WCAG 2.2 AA), and give every
  control a visible focus state.
- **Do** keep motion between 140ms (presses) and 280ms (the name morph) on the strong ease-out
  curve (cubic-bezier(0.23, 1, 0.32, 1)), and honor prefers-reduced-motion with an instant,
  non-animated fallback.

### Don't:
- **Don't** build anything that reads as a social network -- no feeds, likes, follower counts,
  activity streams, or engagement mechanics. Euno is a private room, not a stage.
- **Don't** build anything that reads as a CRM or sales tool -- no pipelines, deal stages, lead
  scoring, or dashboards of metrics. These are relationships, not leads.
- **Don't** show a health score, closeness ranking, streak, or "reconnect before you lose them"
  nudge. Euno holds memory; it never grades a relationship.
- **Don't** run Muted gray as body text on a tinted surface; it reads as washed-out and fails
  contrast. Body is Ink.
- **Don't** introduce a second accent hue, a gradient, or gradient text. The system is one blue
  on neutrals.
- **Don't** add ambient drop shadows to ordinary cards and rows, or use a tight dark 2014-style
  shadow anywhere.
