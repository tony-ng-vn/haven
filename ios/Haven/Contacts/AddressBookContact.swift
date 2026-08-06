import Foundation

/// One person read from the device's address book, reduced to what matching
/// and import need -- no address, no birthday, nothing that never becomes
/// part of a Haven capture. The same shape `VCardContact.Parsed` reduces a
/// shared card to, because a device contact and a shared vCard answer the
/// same question: who is this, and what is the one way to reach them.
struct AddressBookContact: Equatable, Sendable, Identifiable {
    /// `CNContact.identifier`. Stable for a given contact on this device, and
    /// always readable regardless of which keys were fetched -- unlike every
    /// other property here, which needs `keysToFetch` to include it or reading
    /// it throws an Objective-C exception Swift cannot catch.
    let id: String
    let name: String
    let phones: [String]
    let emails: [String]
}
