import Contacts
import Foundation

/// The real address book: the only part of contact matching that touches
/// `CNContactStore`. Everything above this is pure and tested against
/// `AddressBookProviding` instead -- the same split `ConvexCaptureSink` draws
/// against `CaptureSink`.
struct LiveAddressBook: AddressBookProviding {
    /// Exactly the properties `AddressBookContact` reads. Declared once and
    /// reused everywhere a `CNContact` is fetched: reading a property outside
    /// this list throws `CNContactPropertyNotFetchedException`, an
    /// Objective-C exception Swift cannot catch, so the set actually fetched
    /// and the set actually read must never drift apart.
    static let keysToFetch: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func search(matching query: String) async throws -> [AddressBookContact] {
        let trimmed = query.trimmedLikeJS
        guard !trimmed.isEmpty else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            // A dictionary keyed on identifier, not an array: a name match
            // and a phone match can both return the same person, and a
            // second row for the same contact would read as a bug.
            var found: [String: CNContact] = [:]
            for contact in try store.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingName: trimmed),
                keysToFetch: Self.keysToFetch
            ) {
                found[contact.identifier] = contact
            }
            // A query that could be a phone number is also tried as one:
            // CNPhoneNumber's predicate normalizes formatting the way a name
            // match never would, which is what lets "415 555" find someone
            // saved as "(415) 555-....".
            if trimmed.contains(where: \.isASCIIDigit) {
                let phoneNumber = CNPhoneNumber(stringValue: trimmed)
                for contact in try store.unifiedContacts(
                    matching: CNContact.predicateForContacts(matching: phoneNumber),
                    keysToFetch: Self.keysToFetch
                ) {
                    found[contact.identifier] = contact
                }
            }
            return found.values.map(Self.reduce)
        }.value
    }

    func contacts(withIdentifiers identifiers: [String]) async -> [AddressBookContact] {
        guard !identifiers.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
            guard
                let contacts = try? store.unifiedContacts(
                    matching: predicate, keysToFetch: Self.keysToFetch
                )
            else { return [] }
            return contacts.map(Self.reduce)
        }.value
    }

    /// A snapshot diff, not real change history.
    ///
    /// `CNContactStore`'s actual change-history enumerator --
    /// `enumeratorForChangeHistoryFetchRequest:error:`, the only method that
    /// walks `CNChangeHistoryEvent`s -- is declared `NS_SWIFT_UNAVAILABLE("")`
    /// in `CNContactStore.h` on every SDK checked for this repo (confirmed
    /// against the iOS 26.5 simulator SDK headers directly), with no
    /// Swift-visible alternative. Swift code cannot call it, full stop, so
    /// this answers the same product question -- "who is new since I last
    /// looked" -- by enumerating every currently visible identifier and
    /// diffing it against the set from the last check instead of walking an
    /// incremental log. One lightweight key, on a background priority, so
    /// the cost of the full enumeration this trades for is one array of
    /// strings rather than a stream of fully hydrated contacts.
    ///
    /// `CNContactStore.currentHistoryToken` is still read and handed back,
    /// even though nothing consults it yet: it costs nothing to keep, and it
    /// is what a future native implementation -- an Objective-C shim calling
    /// the unavailable method directly -- would need on day one.
    func newlySeenContacts(knownIdentifiers: Set<String>?) async -> ContactDiscovery {
        await Task.detached(priority: .utility) {
            let store = CNContactStore()
            let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
            var identifiers: Set<String> = []
            guard (try? store.enumerateContacts(with: request) { contact, _ in
                identifiers.insert(contact.identifier)
            }) != nil else {
                // A read that fails is not a crash and not a suggestion --
                // the previous baseline stands untouched, and there is
                // nothing new to report this time.
                return ContactDiscovery(added: [], allIdentifiers: knownIdentifiers ?? [], historyToken: nil)
            }
            let newIds = ContactIdentifierDiff.added(current: identifiers, knownBefore: knownIdentifiers)
            // Full details for only the ones that are actually new, through
            // the exact call `ContactAccessButton`'s approval and the
            // picker's selection already make -- one place in this file
            // fetches a fully keyed `CNContact`, and one list of keys it can
            // ever be missing.
            let added = newIds.isEmpty ? [] : await LiveAddressBook().contacts(withIdentifiers: Array(newIds))
            return ContactDiscovery(added: added, allIdentifiers: identifiers, historyToken: store.currentHistoryToken)
        }.value
    }

    /// A `CNContact` reduced the same way `VCardContact` reduces a parsed
    /// card: given and family name joined plainly, the organization when a
    /// card has neither.
    static func reduce(_ contact: CNContact) -> AddressBookContact {
        let personal = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return AddressBookContact(
            id: contact.identifier,
            name: personal.isEmpty ? contact.organizationName : personal,
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { String($0.value) }
        )
    }
}
