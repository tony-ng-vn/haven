import Foundation

/// Bookkeeping for "Haven could not fully save what you shared": every
/// capture whose outcome needs a user-visible notice, oldest first.
///
/// App Group defaults, the same bookkeeping style `ContactChangeState` uses
/// -- not `.standard`, even though only the app reads or writes this today.
/// Injectable rather than always reaching for the real suite, the same
/// reason `CaptureQueue` takes a directory rather than assuming one: a test
/// that wrote here would otherwise leak into every other test's
/// `UserDefaults.standard`.
///
/// A small FIFO rather than the one pending slot this used to be: a single
/// drain pass can produce more than one notice -- a handle-cap drop on one
/// capture and a final conflict on another -- and overwriting one with the
/// other was exactly the silent loss this type exists to prevent. Capped in
/// the single digits: nobody has that many surprises waiting at once, and an
/// unbounded queue would be its own bug to explain later.
struct HandleDropState {
    private let defaults: UserDefaults
    private let userId: String

    /// How many notices are kept before the oldest is evicted to make room
    /// for a new one. See the type's doc comment for why single digits.
    static let capacity = 5

    init(userId: String, defaults: UserDefaults = HandleDropState.appGroupDefaults) {
        self.userId = userId
        self.defaults = defaults
    }

    /// App Group defaults when the group is provisioned, `.standard`
    /// otherwise -- the same fallback `CaptureQueue.forApp()` and
    /// `ContactChangeState` use, so a device missing the entitlement still
    /// remembers this for the life of the install rather than losing the
    /// feature outright.
    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: HavenAppGroup.identifier) ?? .standard
    }

    /// Posted whenever `record` or `dismiss` changes what is pending, with
    /// the `userId` this fired for as the notification's `object` -- the
    /// same scoping the storage key itself uses, so a screen for one account
    /// ignores a drain that ran for another one signed in on the same
    /// device. Lets a screen already on hand (`DirectoryScreen`) update the
    /// moment a foreground drain finishes, instead of only on its own next
    /// poll.
    static let didChangeNotification = Notification.Name("HandleDropState.didChange")

    /// One capture Haven could not fully save.
    struct Event: Equatable, Sendable {
        /// Why this capture needs a notice, so the screen can show copy
        /// that actually matches what happened instead of one generic
        /// message stretched to cover two different problems.
        enum Reason: String, Sendable {
            /// The account named landed on a person, but that person was
            /// already at the 8-handle cap -- this one account did not fit.
            case handleFull
            /// The whole capture landed nowhere: the handle it named
            /// already, provably, belongs to somebody else.
            case conflict
        }
        let personId: String
        let personName: String
        let platform: String
        let reason: Reason
    }

    /// The oldest notice nobody has dismissed yet, or nil. Oldest first: it
    /// is the one that has been waiting longest, and it is what `dismiss()`
    /// removes.
    var pending: Event? {
        queued.first
    }

    /// Queues a notice, evicting the oldest if this would grow past
    /// `capacity`. A no-op when an identical event is already queued --
    /// `ConflictNoticeMarks` is what actually keeps a replayed conflict
    /// from reaching here a second time, but this is the belt: two
    /// different captures that happen to produce identical-looking events
    /// (same person, platform, and reason) still collapse to one notice
    /// instead of showing the same sentence twice.
    func record(_ event: Event) {
        var events = queued
        guard !events.contains(event) else { return }
        events.append(event)
        if events.count > Self.capacity {
            events.removeFirst(events.count - Self.capacity)
        }
        save(events)
        postChange()
    }

    /// Drops the oldest notice, surfacing whichever was queued behind it. A
    /// no-op, not an error, when nothing is pending.
    func dismiss() {
        var events = queued
        guard !events.isEmpty else { return }
        events.removeFirst()
        save(events)
        postChange()
    }

    private var queued: [Event] {
        guard let data = defaults.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([Event].self, from: data)) ?? []
    }

    private func save(_ events: [Event]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: queueKey)
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: userId)
    }

    private var queueKey: String { "haven.captures.droppedHandle.\(userId)" }
}

extension HandleDropState.Event: Codable {}
extension HandleDropState.Event.Reason: Codable {}
