import Foundation

/// Whether a queued capture's last-known conflict has already produced a
/// user-visible notice.
///
/// A capture that ends in a final conflict (see `ConflictRetry` and
/// `CaptureDrain.process(...)`) stays in the queue on purpose -- the same
/// retained-for-retry treatment a network failure gets -- so the drain
/// attempts it again on every later pass. Attempting it again is right;
/// recording a fresh notice every time it comes back "conflict" again is
/// not: the person already saw the banner (dismissed it or not), and a
/// replay of the same unresolved problem is not new information. Left
/// unchecked, a capture stuck in conflict resurrects a dismissed banner on
/// every launch and can crowd unrelated notices out of `HandleDropState`'s
/// capacity-5 FIFO.
///
/// App Group defaults, the same bookkeeping style `HandleDropState` uses,
/// scoped by `userId` the same way -- but keyed on the queued capture's own
/// `id` (a `UUID`, stable for as long as the capture stays queued), not on
/// anything about the conflict itself. The question this answers is "has
/// *this capture* already told the person about a conflict", not which
/// person or platform it named.
struct ConflictNoticeMarks {
    private let defaults: UserDefaults
    private let userId: String

    /// Production callers (`CaptureSync.run(userId:)`) must always pass the
    /// real signed-in `userId` here. `CaptureDrain`'s own struct-level
    /// default constructs one scoped to a fresh random id purely so the
    /// tests that do not care about conflict bookkeeping can construct a
    /// `CaptureDrain` without one -- it can never observe another
    /// instance's marks, which also means it can never suppress a repeat
    /// notice. That silent no-op is correct for those tests and wrong for
    /// production, which is why `CaptureSync` constructs its own explicitly
    /// rather than relying on `CaptureDrain`'s default.
    init(userId: String, defaults: UserDefaults = HandleDropState.appGroupDefaults) {
        self.userId = userId
        self.defaults = defaults
    }

    /// Whether this capture's conflict already produced a notice on an
    /// earlier pass.
    func hasNotified(_ captureId: UUID) -> Bool {
        marked.contains(captureId.uuidString)
    }

    /// Marks this capture's conflict as reported, so a later pass that
    /// replays the same conflict does not notify again.
    func markNotified(_ captureId: UUID) {
        var ids = marked
        guard ids.insert(captureId.uuidString).inserted else { return }
        save(ids)
    }

    /// The capture resolved to something other than a conflict -- landed,
    /// or was dropped outright -- so whatever mark it carried no longer
    /// describes it. A capture that was never marked is left untouched, so
    /// every resolution can call this unconditionally rather than checking
    /// `hasNotified` first. Bookkeeping hygiene more than a behavior change:
    /// a resolved capture is removed from the queue and its UUID never
    /// recurs, so an uncleared mark would just grow this set forever rather
    /// than actually causing a wrong suppression.
    func clear(_ captureId: UUID) {
        var ids = marked
        guard ids.remove(captureId.uuidString) != nil else { return }
        save(ids)
    }

    /// Read fresh on every access rather than cached: two `ConflictNoticeMarks`
    /// values constructed for the same `userId` (one per drain pass, the way
    /// `CaptureSync` makes a new one each `run(userId:)` call) must agree on
    /// what is marked, and only reading the underlying store each time
    /// guarantees that.
    private var marked: Set<String> {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    private func save(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        defaults.set(data, forKey: key)
    }

    private var key: String { "haven.captures.conflictNotified.\(userId)" }
}
