import Foundation
import os

/// Timing breadcrumbs for the handful of milestones between the process
/// starting and the first real screen appearing: `HavenApp.init`,
/// `LaunchGate`'s first body (the first frame actually painted), `Clerk`
/// configuring starting and finishing behind that frame, `RootView`'s first
/// body, the first Clerk auth-state resolution, the first `profiles:getMyCard`
/// result (or its failure), and the first appearance of `OnboardingFlow` and
/// of `HavenTabs`.
///
/// Launch only. Every call site is one line and fires once -- `markOnce`
/// itself is the guard, not the caller, so a view whose body runs on every
/// state change (which is most of them) never needs its own "have I already
/// logged this" flag, and this never turns into a per-frame log.
///
/// The clock starts at first use, not at the OS process fork: getting the
/// literal fork time needs a heavier API for a few milliseconds of accuracy
/// nothing here is chasing. In practice the first call is the first line of
/// `HavenApp.init`, which is as close to process start as Swift code runs.
///
/// `@MainActor` because `logged` is a plain, unsynchronized `Set`: every
/// call site today already runs on the main actor (`HavenApp.init`,
/// `LaunchGate`/`RootView`'s bodies, `AuthModel`'s init, view `.task`
/// closures), so this enforces an invariant that already holds rather than
/// changing one -- it just stops a future off-main call site from racing
/// `logged`'s insert against another one instead of that becoming a launch
/// heisenbug months from now.
@MainActor
enum LaunchLog {
    private static let logger = Logger(subsystem: "com.inhavens.haven", category: "launch")
    /// Monotonic, and unaffected by the system clock changing underneath a
    /// launch -- unlike `Date()`, which a clock change could move backward.
    private static let start = DispatchTime.now()
    private static var logged = Set<String>()

    static func markOnce(_ milestone: String) {
        guard logged.insert(milestone).inserted else { return }
        // `start` read into a local first, deliberately: on the very first
        // call ever, `start` has not been touched yet and its lazy init runs
        // right here. Reading it before `DispatchTime.now()` guarantees `now`
        // -- captured strictly afterward -- is never earlier than `start`.
        // Read in the other order (as the original version of this file did),
        // the two land the other way around on that first call, and the
        // subtraction below underflows a UInt64 and traps: this crashed every
        // launch until it was caught by an actual device crash log.
        let startNanos = start.uptimeNanoseconds
        let nowNanos = DispatchTime.now().uptimeNanoseconds
        let elapsedMs = Double(nowNanos - startNanos) / 1_000_000
        // Public on both fields: neither a milestone name nor a duration is
        // user data, and Console.app shows a private field as "<private>"
        // without a special logging profile -- the whole point here is that
        // these lines are readable by default.
        logger.info(
            "\(milestone, privacy: .public): +\(elapsedMs, format: .fixed(precision: 1), privacy: .public)ms"
        )
    }
}
