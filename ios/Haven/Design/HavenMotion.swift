import SwiftUI

// The durations Phase 1 uses, and one rule about Reduce Motion.
//
// Reduce Motion does not mean "no state change". It means the change arrives
// instantly instead of being animated. Use `havenAnimation(_:value:)` rather
// than `.animation(_:value:)` and that is handled for you.
enum HavenMotion {
    /// A strong ease-out. Everything decelerates into place; nothing overshoots.
    /// Matches the prototype's cubic-bezier(0.23, 1, 0.32, 1).
    static func easeOut(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    static let pressDuration: TimeInterval = 0.14
    static let screenDuration: TimeInterval = 0.24
    /// A star coming on when a field commits.
    static let starIgnitionDuration: TimeInterval = 0.85
    /// How long anything waiting on that ignition actually waits.
    ///
    /// Not the same number, and the difference is the point. Sampled,
    /// `timingCurve(0.23, 1, 0.32, 1)` over 0.85s is 89 percent done at 0.30s
    /// and 96 percent at 0.40s: the last 0.45s is a curve asymptoting where
    /// nobody can see it. Two separate sleeps -- `HavenScreen.ignite` and
    /// `OnboardingModel.commit` -- were both holding the app's signature moment
    /// for all of it, which is about half a second of dead air per answered
    /// question.
    ///
    /// The curve keeps its shape; only the waiting is cut. Both sleeps read
    /// this one constant, so the beat cannot drift between them.
    static let starIgnitionHold: TimeInterval = 0.40
    /// The card reveal settling. The token lives here; the reveal itself is
    /// milestone 1 and is judged on a device.
    static let revealSettleDuration: TimeInterval = 1.1

    /// The one spring in Haven, and the audit that says why there is one.
    ///
    /// A timing curve restarts at zero velocity when it is interrupted, which
    /// reads as a hitch mid-gesture. That only matters where a finger can catch
    /// something already moving, so every animation in the app was checked:
    /// the reveal, the star ignition, the sky's shimmer, every screen
    /// transition, the promo cards, the focus rings and the press scales are
    /// all one-shot or gesture-free, and a curve is the right shape for them.
    /// The card flip is the exception -- it is a tap that toggles, so a second
    /// tap lands while the first is still turning.
    ///
    /// The review that asked for springs asked for them everywhere, against a
    /// tilted card that could be grabbed and spun. That card went in PR 134, so
    /// this is re-derived from the interactions that exist rather than adopted
    /// from the finding. Response and damping are the numbers the reviewers
    /// converged on.
    static let interruptible = Animation.spring(response: 0.4, dampingFraction: 0.8)

    static let press = easeOut(pressDuration)
    static let screen = easeOut(screenDuration)
    static let starIgnition = easeOut(starIgnitionDuration)
    static let revealSettle = easeOut(revealSettleDuration)
    /// Interruptible, unlike everything else here: see `interruptible`.
    static let cardFlip = interruptible
}

extension View {
    /// `.animation(_:value:)` that respects Reduce Motion.
    func havenAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(HavenAnimationModifier(animation: animation, value: value))
    }

    /// Stops the ambient loops below this point.
    ///
    /// Set it while something covers the screen -- an editor sheet, an alert.
    /// A `TimelineView` behind a presented sheet keeps waking at display rate
    /// to redraw a sky nobody can see, and the card screen can have two of them
    /// running at once.
    func havenAmbientPaused(_ paused: Bool) -> some View {
        environment(\.havenAmbientPaused, paused)
    }

    /// Forces the Reduce Motion path on. This exists so previews can show the
    /// still version of a screen: SwiftUI's own `accessibilityReduceMotion` is
    /// read-only, so there is no other way to look at it.
    func havenReduceMotion(_ enabled: Bool = true) -> some View {
        environment(\.havenReduceMotionOverride, enabled)
    }
}

/// Reads the system Reduce Motion setting, unless something up the hierarchy has
/// overridden it. Use this instead of `@Environment(\.accessibilityReduceMotion)`
/// so every surface can be previewed both ways.
@propertyWrapper
struct HavenReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.havenReduceMotionOverride) private var override

    var wrappedValue: Bool { override ?? system }
}

extension EnvironmentValues {
    fileprivate(set) var havenReduceMotionOverride: Bool? {
        get { self[HavenReduceMotionOverrideKey.self] }
        set { self[HavenReduceMotionOverrideKey.self] = newValue }
    }

    /// Whether ambient loops should stop. See `havenAmbientPaused(_:)`.
    ///
    /// Distinct from Reduce Motion: that is a person's standing preference and
    /// removes the motion permanently, this is momentary and only means the
    /// screen is covered.
    fileprivate(set) var havenAmbientPaused: Bool {
        get { self[HavenAmbientPausedKey.self] }
        set { self[HavenAmbientPausedKey.self] = newValue }
    }
}

private struct HavenReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct HavenAmbientPausedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct HavenAnimationModifier<V: Equatable>: ViewModifier {
    @HavenReduceMotion private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
