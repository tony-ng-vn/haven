import Contacts
import Foundation

/// What a contact-matching section has to show: the authorization level, and
/// whatever rows are worth offering at that level.
struct ContactMatchState: Equatable {
    let status: CNAuthorizationStatus
    let rows: [AddressBookContact]
    /// True when the last search threw rather than answered -- shown rather
    /// than swallowed into an empty result list, which would read as "no
    /// matches" and is a different fact.
    let searchFailed: Bool

    static func idle(status: CNAuthorizationStatus) -> ContactMatchState {
        ContactMatchState(status: status, rows: [], searchFailed: false)
    }
}

/// Drives one contact-matching section: search-as-you-type over the address
/// book, reduced to rows worth an import tap, plus the plumbing
/// `ContactAccessButton` and the classic picker both need to reveal more.
///
/// Deliberately thin -- every decision worth testing on its own terms
/// (`ContactImportMatching`) lives above this, in code that never imports
/// `Contacts` at all. This is glue: which state to be in, and what a tap
/// does about it.
@MainActor
final class ContactMatchModel: ObservableObject {
    @Published private(set) var state: ContactMatchState
    let ignoredPhoneNumbers: Set<String>
    let ignoredEmails: Set<String>

    private let provider: AddressBookProviding
    private let queue: CaptureQueue
    /// Read once at presentation time, the same way `AddPersonSheet` reads
    /// its own copy: a cache that goes stale the moment somebody else's
    /// capture drains is an acceptable staleness here, because
    /// `enqueueImport` re-checks it and the server dedups on the handle
    /// either way.
    private let mirror: DirectoryMirror?

    init(
        provider: AddressBookProviding = LiveAddressBook(),
        queue: CaptureQueue = .forApp(),
        mirror: DirectoryMirror?
    ) {
        self.provider = provider
        self.queue = queue
        self.mirror = mirror
        let known = mirror?.knownPhonesAndEmails ?? (phones: [], emails: [])
        ignoredPhoneNumbers = known.phones
        ignoredEmails = known.emails
        state = .idle(status: provider.authorizationStatus())
    }

    /// Runs one search, or clears back to idle for a blank query.
    ///
    /// Debounced the same way `SearchModel`'s own field is: the caller
    /// attaches this to `.task(id: query)`, which cancels the running call
    /// the moment another keystroke changes `query`, so the sleep below is
    /// what collapses a burst of keystrokes into one store query instead of
    /// one per character -- `CNContactStore.unifiedContacts` is not free,
    /// and it does not belong on the main-actor-hopping path of every single
    /// character somebody types.
    ///
    /// Never reaches `provider.search` under
    /// `.denied`/`.restricted`/`.notDetermined` -- that call is documented
    /// not to be made speculatively, and this is the one place that could
    /// break that.
    func search(_ query: String) async {
        do {
            try await Task.sleep(for: SearchModel.debounce)
        } catch {
            return
        }
        let status = provider.authorizationStatus()
        let trimmed = query.trimmedLikeJS
        guard !trimmed.isEmpty, status == .authorized || status == .limited else {
            state = .idle(status: status)
            return
        }
        do {
            let matches = try await provider.search(matching: trimmed)
            let candidates = ContactImportMatching.importCandidates(from: matches, mirror: mirror)
            state = ContactMatchState(status: status, rows: candidates, searchFailed: false)
        } catch {
            state = ContactMatchState(status: status, rows: [], searchFailed: true)
        }
    }

    /// Folds contacts `ContactAccessButton` or the picker just granted
    /// visibility into into the rows already on screen.
    ///
    /// Not an import: revealing is what the tap on the button or the picker
    /// asked for, and the one tap every other row gets to actually save
    /// somebody is still `enqueueImport`. Re-reads authorization, because a
    /// grant through the button moves status from `.notDetermined` to
    /// `.limited`, which changes whether the button itself keeps showing.
    func reveal(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        let revealed = await provider.contacts(withIdentifiers: identifiers)
        let candidates = ContactImportMatching.importCandidates(from: revealed, mirror: mirror)
        var merged = state.rows
        for candidate in candidates where !merged.contains(where: { $0.id == candidate.id }) {
            merged.append(candidate)
        }
        state = ContactMatchState(status: provider.authorizationStatus(), rows: merged, searchFailed: state.searchFailed)
    }

    /// What the classic picker's one-contact selection does: prefer a fresh
    /// store fetch by identifier, and fall back to the contact the picker's
    /// own delegate already handed over when that fetch does not succeed.
    ///
    /// That fallback is not a nicety here, it is the only path that works:
    /// the classic picker is shown only under `.denied`/`.restricted`
    /// (`ContactPicker`'s own doc comment), and `provider.contacts` is
    /// refused outright by `CNContactStore` at both of those authorization
    /// levels. `delegateContact` is what the picker's own privilege already
    /// handed the app, independent of the app's own authorization -- without
    /// using it directly, nothing the classic picker offers could ever
    /// actually import.
    func importPicked(_ delegateContact: AddressBookContact) async -> Bool {
        let fetched = await provider.contacts(withIdentifiers: [delegateContact.id])
        return enqueueImport(fetched.first ?? delegateContact)
    }

    /// Queues the one-tap import: the same `.manual` capture a shared vCard
    /// already writes through. True once it is on disk -- the caller asks
    /// for a drain only then, the same "receipt" rule the share sheet and
    /// `AddPersonSheet` already follow.
    ///
    /// Re-checks the mirror rather than trusting a row that was already
    /// filtered when it first appeared: a contact `ContactAccessButton` or
    /// the picker just revealed was matched against the mirror snapshot from
    /// before the tap, and this is the same defense-in-depth the server's
    /// own dedup on the handle already provides -- belt and suspenders, not
    /// a second source of truth.
    func enqueueImport(_ contact: AddressBookContact) -> Bool {
        guard
            ContactImportMatching.alreadyInHaven(contact, mirror: mirror) == nil,
            let capture = ContactImportMatching.capture(for: contact)
        else { return false }
        return (try? queue.enqueue(capture)) != nil
    }
}
