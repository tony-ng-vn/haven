import Foundation

/// Bookkeeping for "you added someone to your contacts": the change-history
/// token, so the next foreground only asks Contacts what changed since last
/// time, and which contacts have already been offered and turned down.
///
/// App Group defaults, alongside the container the directory mirror and the
/// capture queue already live in -- not `.standard`, even though only the app
/// reads or writes this today. Injectable rather than always reaching for the
/// real suite, the same reason `CaptureQueue` takes a directory rather than
/// assuming one: a test that wrote here would otherwise leak into every other
/// test's `UserDefaults.standard`.
struct ContactChangeState {
    private let defaults: UserDefaults
    private let userId: String

    init(userId: String, defaults: UserDefaults = ContactChangeState.appGroupDefaults) {
        self.userId = userId
        self.defaults = defaults
    }

    /// App Group defaults when the group is provisioned, `.standard`
    /// otherwise -- the same fallback `CaptureQueue.forApp()` uses, so a
    /// device missing the entitlement still remembers dismissals for the life
    /// of the install rather than losing the feature outright.
    static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: HavenAppGroup.identifier) ?? .standard
    }

    /// `CNContactStore.currentHistoryToken` as of the last successful check.
    ///
    /// Persisted even though nothing reads it back today:
    /// `CNContactStore`'s own change-history enumerator is marked
    /// unreachable from Swift on every SDK this repo has checked (see
    /// `LiveAddressBook`'s doc comment), so `newlySeenContacts` diffs a
    /// snapshot of every visible identifier instead of walking history from
    /// a token. The token itself is still Swift-readable and costs nothing
    /// to keep -- it is what a future native implementation would need, and
    /// there is no reason to throw away a fact this cheap to remember.
    var historyToken: Data? {
        get { defaults.data(forKey: tokenKey) }
        nonmutating set { defaults.set(newValue, forKey: tokenKey) }
    }

    /// Every contact identifier visible at this authorization level as of
    /// the last successful check, or nil before the first one.
    ///
    /// The nil case is load bearing: without a baseline to diff against,
    /// every contact on the device would read as newly added the first time
    /// Haven ever looks, which is not what "you added Dun Dun" is supposed
    /// to mean. See `ContactIdentifierDiff`.
    var knownContactIdentifiers: Set<String>? {
        (defaults.array(forKey: knownIdentifiersKey) as? [String]).map(Set.init)
    }

    func recordKnownContactIdentifiers(_ identifiers: Set<String>) {
        defaults.set(Array(identifiers), forKey: knownIdentifiersKey)
    }

    /// Whether this contact has already been suggested and dismissed, so it
    /// is never asked about twice.
    func isDismissed(_ contactId: String) -> Bool {
        dismissedIds.contains(contactId)
    }

    func dismiss(_ contactId: String) {
        var ids = dismissedIds
        guard ids.insert(contactId).inserted else { return }
        defaults.set(Array(ids), forKey: dismissedKey)
    }

    private var dismissedIds: Set<String> {
        Set(defaults.stringArray(forKey: dismissedKey) ?? [])
    }

    private var tokenKey: String { "haven.contacts.historyToken.\(userId)" }
    private var knownIdentifiersKey: String { "haven.contacts.knownIdentifiers.\(userId)" }
    private var dismissedKey: String { "haven.contacts.dismissedSuggestions.\(userId)" }
}
