# Card design review, 27 July 2026

Nine UI and interface skills run independently against the "Your card" screen after the Stage 1 card-object rebuild (PR #115).
Each reviewer got the real screenshots, the source, and the design intent, and was briefed to translate web rules to their iOS equivalents.

Skills run: `apple-design`, `better-ui`, `better-accessibility`, `better-layout`, `better-typography`, `better-colors`, `emil-design-eng`, `review-animations`, `impeccable`.

Skills deliberately excluded: `baseline-ui` (Tailwind-only), `canvas-design` (posters), `grilling-frontend-prototyping` (HTML variants), `design-an-interface` (code APIs, not UI).

Note: six of the nine are set to `"off"` in `~/.claude/settings.json`, so the agents read each `SKILL.md` from disk instead of invoking it.
Same content, but worth knowing.

## Verified before relaying

These were checked directly rather than taken on the reviewer's word.

**The photo never reaches the card.**
`HavenCard` declares `photo: Image?` at `HavenCard.swift:30`, but neither real call site passes it: `MyCardScreen.swift:99` and `CardRevealScreen.swift:36` both omit the argument.
Only previews supply it.
So a photo uploads, the row flips to "Added", the photo star lights, and the card face never changes -- on your own card and on the card other people see.
This is the screen's central promise failing on the field that would change it most.

**The ACCOUNT label fails contrast where it actually sits.**
Computed by hand: `faint` #767C9C measures 4.57:1 over `night` #0E1123 and 3.40:1 over `dusk` #232A4D.
The label renders near the bottom of the scroll where the background gradient is dusk-ward, and at ~11pt the bar is 4.5:1.
So it fails in place.
Two reviewers flagged it and one said it passed -- the one that said it passed measured against `night` only.

**Previews are about 19% wider than the shipping card.**
Card previews pad by 44pt, but the real screen adds `HavenScreen`'s own 24pt on top, so the card is 257pt wide in the app and 305pt in every preview.
Every type and layout judgement made from a preview has been made at the wrong width.

**iPad is a supported destination with an unbounded card.**
`TARGETED_DEVICE_FAMILY = "1,2"` appears six times in the project.
`MyCardMetrics.cardInset` is a fixed 44pt off an unbounded width, and height follows from the 0.64 aspect, so a 12.9" iPad in landscape computes to a card roughly twice the height of the screen.

## Consensus findings

Ordered by how many independent reviewers reached them.

### Six reviewers: `reduceMotion` is dead and its comment is false

`CardObject.swift:16` declares `@HavenReduceMotion private var reduceMotion` and nothing reads it.
The comment at lines 21-23 claims "both accessibility settings land on the same path", but `isFlat` at line 24 reads only `dynamicTypeSize`.
Swift does not warn on an unused stored property in a View, so this rots silently.

Harmless while the card is static.
It stops being harmless the moment a gesture ships, because that is the flag that would gate it.

Two defensible fixes, and the reviewers disagree about which is true:

- `isFlat` should be `reduceMotion || dynamicTypeSize >= .accessibility3`.
- A static tilt is not motion, so the tilt should stay and only the gestures should be gated.

Resolved from the codebase rather than by argument.
Two existing precedents both point the same way.
`PressScale` (`HavenButtons.swift:82-93`) suppresses the 0.98 press scale, but that scale only exists while a finger is down -- it is a transient change, and the resting state is already 1.
`AnimatedSky` (`SkyView.swift:186-191`) freezes at its resting midpoint rather than at t=0, deliberately keeping a static non-neutral appearance and removing only the movement.

So Haven's own convention is that Reduce Motion removes change, not resting transforms.
The tilt stays; the gestures get gated.
The comment has to change either way.

### Four reviewers: the card is guillotined on scroll

The nav bar is fully transparent, so the card slides up and is cut by a razor-straight line with nothing there to justify it.
An object sliced by an invisible plane stops reading as an object.

Fix on `MyCardScreen`, not on the shared skeleton: `.toolbarBackground(.visible, for: .navigationBar)` with a material, so the card passes under something.
Do not use `.scrollClipDisabled()` -- the card would then draw over the title.

Related: the scroll indicator runs straight through the card's right rim.

### Four reviewers: the contact circles are sized for a tap target they do not have

`CardMetrics.contactDiameter = 44` with a `hairlineStrong` ring makes the platform marks look exactly like buttons.
They do nothing.
They also over-fill: 4x44 + 3x12 = 212pt inside roughly 210pt of usable face width, so the row has zero slack.

And they are the only text on the card that ignores Dynamic Type -- `PlatformMark` hardcodes `.system(size: 15/14/13)` while `photoDiameter` directly above it is already `@ScaledMetric`.

Recommended: diameter 36 as a `@ScaledMetric`, relative text styles for the glyphs, and a warmer ring than a separator token.

### Four reviewers: there are no springs anywhere in the app

`HavenMotion` is four fixed-duration `timingCurve` tokens.
A grabbable object cannot be an ease-out: timing curves restart at zero velocity when interrupted, which reads as a hitch mid-gesture.

Proposed values cluster tightly across reviewers: roughly `.spring(response: 0.4, dampingFraction: 0.8)` on release and an `.interactiveSpring` while the finger is down.

### Three reviewers: empty and filled rows are indistinguishable

`MyCardScreen.swift:149` passes `value ?? field.placeholder` into one `detail`, both rendered in `havenSecondary()`.
"Where you work" and "San Francisco, CA" are the same weight and colour.

Meanwhile `spoken(_:value:)` at line 172 tells VoiceOver "Company, empty" outright.
Screen reader users get strictly more information than sighted users, which is backwards, and it means the unlit-star nudge has no visual counterpart in the rows that are supposed to explain it.

### Three reviewers: rows are buttons with no affordance

Every row passes `trailing: { EmptyView() }`.
All six open sheets.
Nothing but the press highlight says so.
`HavenRow` already gives VoiceOver the `.isButton` trait, so again the screen tells the screen reader more than it tells the eye.

### Two reviewers: "Delete your account" is one hairline below "Role"

Same row style, same colour, no destructive tint, no separation, on a screen someone opens to fix a typo in their name.

## Single-reviewer findings worth acting on

**The star ignition holds for twice as long as the animation.**
Sampled: `timingCurve(0.23, 1, 0.32, 1)` is 89% done at 0.30s and 96% at 0.40s, but `HavenScreen.swift:209` and `OnboardingModel.swift:256` both sleep the full 0.85s.
Roughly half a second of dead air in the app's signature moment.
Also two separate timers own the same beat, sharing only a constant.

**At accessibility3 the card loses its silhouette.**
`isFlat` drops the `edge` entirely and flattens the light, leaving `specular`, whose top stop is `HavenColor.hairline` at white 0.10.
Card face against page ground is 1.13:1 and the stroke lands at 1.53:1, so the card's upper edge effectively disappears at the largest text sizes.

**A long name at accessibility sizes can collapse the constellation.**
The text column is 201pt wide.
At AX3 a name like "Maria Fernanda Rodriguez" wraps to about five lines, and the measured foot then squeezes `figureBand` toward zero.
The failure mode is the sky silently vanishing rather than text clipping, which is easy to miss.
The existing AX3 preview uses "Maya Chen", which is short enough to hide it.

**The serif does not cover every name.**
New York handles Latin and Vietnamese diacritics well but has no CJK, Thai, Devanagari or Arabic coverage, so those names fall back to the sans face.
The one brand rule -- serif for names -- does not hold for a large share of users.
Do not fake a serif to compensate.

**The rim out-shouts the constellation.**
`CardObject.swift:9-13` and `MyCardScreen.swift:9-13` both say the sky is the uniquely personal thing, and the gold rim at `star.opacity(0.55)` is the brightest element on screen.
The code contradicts its own stated priority.

**The card has no shadow.**
There is no `.shadow` anywhere in the app.
A tilted slab with a lit edge and no contact shadow reads as a sticker.
A shadow whose offset tracks the tilt is most of what would sell a spin.

**The rim's bottom edge is uniform where it should modulate.**
Sampled across the bottom rim, luminance is 0.640 / 0.643 / 0.643 / 0.638 / 0.641 -- dead flat -- while the right edge over the same card runs 0.375 to 0.713.
Cause: the light axis is near-vertical at rest, so the whole bottom edge samples one gradient stop.
Separately, all seven slabs are translucent, so the outermost sliver dissolves over ~15px instead of ending in a line.

## Settled: the card name is not a contrast risk

One reviewer estimated the city line could fall to about 3.0:1 over an unlucky nebula.
Another swept all 13,824 possible hue triples at every vertical position from 40% to 85% down the card and measured a worst case of 11.42:1 for the name, 6.20-6.53:1 for the city.
Undamped, the name floor is still 10.99:1.

The measured sweep wins over the estimate.
`cardNebulaDamping = 0.5` is an aesthetic control, exactly as its comment claims, not a safety mechanism.
No seed can make the name hard to read.

## The two open decisions

Both are the user's call, not the reviewers'.

### Flip to QR

Two reviewers argue for cutting it.

`BeaconScreen` raises screen brightness to full on appear and again on `scenePhase` change, and that is the thing that makes a code scan in a dim bar.
A card back inside a scroll view at ambient brightness cannot do it.
Reaching it also costs three steps rather than one toolbar tap.

The sharper argument: `FeatureFlags.beaconEnabled` is `false` in DEBUG because debug writes to a deployment the website does not read, so a code generated there resolves to nobody.
A flip would render a scannable code anyway, bypassing the flag -- the exact failure the widget deep link was gated to prevent.
`HavenTabs.swift` already makes this argument in a comment about the widget.

Against cutting: a QR genuinely is what is on the back of a business card, and the flip earns its metaphor in a way a toolbar button never will.
If it ships, the beacon toolbar button should retire, because two doors to one thing is the wrong outcome.

If it ships, three things bite together and were flagged before implementation:

- SwiftUI has no backface culling, so the front renders mirrored through the back.
- `ZStack { edge; face }` paints the slabs behind the face always, so past 90 degrees the thickness appears on the wrong side.
- Seven slabs seen edge-on at 90 degrees fan into a stack of gold cards.

And `lightStart`/`lightEnd` divide by 90 with no clamp, so at a flipped angle the UnitPoints reach -1.64 and 2.64 and the rim washes out to a flat fill.

### Drag to spin

One reviewer says cut it outright: it reveals nothing, changes no state, and the card is the largest touch target on a screen whose primary interaction is scrolling.

Another says drop the vertical axis specifically, because `lightStart`/`lightEnd` vary only in x -- the y components are hardcoded 0.0 and 1.0 -- so a vertical tilt drags the highlight along with the card, which is precisely the illusion-breaker the world-space comment exists to prevent.

Those who would keep it agree on the shape: rubber-band with `limit * tanh(raw / limit)` rather than a hard clamp, band around the resting tilt rather than around zero (crossing y = 0 makes the rim collapse and swap sides mid-drag), no haptics at all, and no animation on the tracked value.

Reduce Motion has no fallback in the current plan.
That is the gap.

On the layout conflict: the recommendation is to pin the card into `HavenScreen`'s header slot below accessibility3 and leave it scrolling at accessibility3 and above, reusing the existing threshold rather than inventing a second one.
At accessibility3 the card is already flat, so there is no spin to protect and pinning would cost most of the viewport on an SE-class device.
