import Foundation

/// Checks, on launch and on every foreground, whether one address-book
/// contact is worth quietly suggesting -- "you added Dun Dun. Add them to
/// Haven?" -- and remembers what was already asked and answered.
///
/// Thin, the same way `ContactMatchModel` is: `ContactSuggestion.pick` and
/// `ContactChangeState` are what is actually tested, and this is the glue
/// that calls them at the right moment and holds the one result.
@MainActor
final class ContactSuggestionModel: ObservableObject {
    @Published private(set) var suggestion: AddressBookContact?

    private let provider: AddressBookProviding
    private let queue: CaptureQueue
    private let changeState: ContactChangeState
    private let mirror: () -> DirectoryMirror?

    init(
        userId: String,
        provider: AddressBookProviding = LiveAddressBook(),
        queue: CaptureQueue = .forApp(),
        // Injectable, the same reason `queue` and `provider` are: a test
        // proving `checkForSuggestion` skips its baseline update under
        // `.limited` needs its own isolated defaults suite, not the real
        // App Group one every other instance of this class shares.
        changeState: ContactChangeState? = nil,
        mirror: @escaping () -> DirectoryMirror? = { DirectoryMirrorStore.forApp().load() }
    ) {
        self.provider = provider
        self.queue = queue
        self.changeState = changeState ?? ContactChangeState(userId: userId)
        self.mirror = mirror
    }

    /// Same cadence `CaptureSync` already runs on: launch, and every return
    /// to the foreground, because coming back from another app is exactly
    /// the moment somebody might have just saved a new contact there.
    ///
    /// Full authorization only, deliberately narrower than `ContactMatchModel`'s
    /// `.authorized || .limited`: this feature's whole premise is an
    /// identifier-diff against the last known set, and under `.limited`
    /// access that set can grow for a reason that has nothing to do with a
    /// new contact existing -- `ContactAccessButton` or the classic picker
    /// granting visibility into a contact that has been in the address book
    /// all along. Under `.limited` there is no way to tell "just added" from
    /// "just became visible" apart from the identifier set alone, so this
    /// skips entirely rather than risk mislabeling the second as the first.
    ///
    /// Degrades silently under `.limited`/`.denied`/`.restricted`/
    /// `.notDetermined` -- no baseline is recorded either, so a grant that
    /// widens what `.limited` can see never gets read back later as
    /// something newly added the moment access is eventually upgraded to
    /// full. There is no error state for a background suggestion, only
    /// "nothing to suggest this time."
    func checkForSuggestion() async {
        let status = provider.authorizationStatus()
        guard status == .authorized else { return }
        let discovery = await provider.newlySeenContacts(
            knownIdentifiers: changeState.knownContactIdentifiers
        )
        if let allIdentifiers = discovery.allIdentifiers {
            changeState.recordKnownContactIdentifiers(allIdentifiers)
        }
        if let token = discovery.historyToken {
            changeState.historyToken = token
        }
        suggestion = ContactSuggestion.pick(
            from: discovery.added, mirror: mirror(), isDismissed: changeState.isDismissed
        )
    }

    /// Taking no for an answer: remembered, so this contact is never
    /// suggested again.
    func dismiss() {
        guard let suggestion else { return }
        changeState.dismiss(suggestion.id)
        self.suggestion = nil
    }

    /// Queues the suggested contact the same one-tap way an import row does.
    /// True once it is on disk, which is also when the suggestion is
    /// cleared -- accepting it is not asking again either.
    func accept() -> Bool {
        guard let suggestion, let capture = ContactImportMatching.capture(for: suggestion) else {
            return false
        }
        guard (try? queue.enqueue(capture)) != nil else { return false }
        changeState.dismiss(suggestion.id)
        self.suggestion = nil
        return true
    }
}
