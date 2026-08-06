import Contacts
import Foundation

/// What one "who is new since I last looked" check found.
struct ContactDiscovery: Equatable, Sendable {
    /// Contacts not present in the identifiers the caller already knew
    /// about. Empty, not "everybody," on the very first check -- see
    /// `ContactIdentifierDiff`.
    let added: [AddressBookContact]
    /// Every contact identifier visible at this authorization level, right
    /// now. The new baseline `ContactChangeState` should remember, whether or
    /// not anything came back in `added`.
    let allIdentifiers: Set<String>
    /// `CNContactStore.currentHistoryToken` as of this check, or nil when the
    /// read failed. Persisted for its own sake -- see `ContactChangeState`'s
    /// doc comment for why nothing reads it back yet.
    let historyToken: Data?
}

/// What contact matching and import need from the address book, wrapped so
/// `ContactImportMatching` and everything above it is testable without
/// `CNContactStore`, a permission prompt, or a real device.
///
/// `LiveAddressBook` is the only conformer that touches the framework; a fake
/// conformer in tests never does.
protocol AddressBookProviding: Sendable {
    func authorizationStatus() -> CNAuthorizationStatus

    /// Name or phone matches, over whatever this authorization level can see.
    /// Never called under `.denied`, `.restricted` or `.notDetermined` --
    /// there is nothing to search yet, and the caller does not call this
    /// speculatively (see `ContactMatchModel`).
    func search(matching query: String) async throws -> [AddressBookContact]

    /// The full contact behind identifiers `ContactAccessButton` just
    /// granted, a picker just returned, or a change-history add event just
    /// named. Best-effort: an identifier Contacts cannot resolve is dropped
    /// rather than failing the whole batch, since a row that never appears is
    /// the same as one silently skipped everywhere else in this pipeline.
    func contacts(withIdentifiers identifiers: [String]) async -> [AddressBookContact]

    /// Contacts not present in `knownIdentifiers`, or all of them read as the
    /// baseline when `knownIdentifiers` is nil.
    ///
    /// Named for what it actually does, not for the change-history API this
    /// repo cannot call from Swift: see `LiveAddressBook`'s doc comment.
    /// Best-effort: a read `.denied`/`.notDetermined` access cannot make
    /// comes back with nothing added rather than throwing -- there is no
    /// user-facing error state for a background suggestion check, only
    /// "nothing to suggest this time."
    func newlySeenContacts(knownIdentifiers: Set<String>?) async -> ContactDiscovery
}
