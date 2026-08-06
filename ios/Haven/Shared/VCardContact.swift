import Contacts
import Foundation

/// What a shared Contacts card reduces to: the fields the share sheet needs
/// and nothing else -- no address, no birthday, no notes, none of which
/// becomes part of a Haven capture.
///
/// vCard 3.0 only, on purpose: that is what Contacts itself exports, and
/// `CNContactVCardSerialization` is unreliable on 4.0. The contact comes back
/// fully materialized rather than fetched with `keysToFetch` the way a
/// `CNContactStore` lookup is, so every property below is safe to read --
/// there is no "not fetched" exception to guard against here.
///
/// Foundation and Contacts only: this is compiled into the share extension,
/// which is why it never asks the OS for permission -- the data is one the
/// user already handed over by sharing it, and CNContactVCardSerialization
/// only ever reads the bytes it was given.
enum VCardContact {
    /// A card reduced to what the share sheet can act on.
    struct Parsed: Equatable, Sendable {
        let name: String
        let phone: String?
        let email: String?
    }

    /// The first contact on the card, or nil when the data does not parse as
    /// a vCard, or parses to nobody worth naming.
    ///
    /// A card can carry more than one contact (a group export); the share
    /// sheet is for the one person somebody just handed over, so only the
    /// first is read.
    static func parse(_ data: Data) -> Parsed? {
        guard let contact = (try? CNContactVCardSerialization.contacts(with: data))?.first
        else { return nil }
        let name = fullName(of: contact)
        guard !name.isEmpty else { return nil }
        return Parsed(
            name: name,
            phone: contact.phoneNumbers.first?.value.stringValue,
            email: contact.emailAddresses.first.map { String($0.value) }
        )
    }

    /// Given and family name, joined the plain way; the organization when a
    /// card carries neither -- a business card is still somebody worth
    /// naming.
    private static func fullName(of contact: CNContact) -> String {
        let personal = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return personal.isEmpty ? contact.organizationName : personal
    }
}
