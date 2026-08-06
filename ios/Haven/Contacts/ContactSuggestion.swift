import Foundation

/// Which identifiers are newly seen, given the identifiers visible right now
/// and the ones remembered from the last check.
///
/// Pure so the one rule that matters -- a first-ever check has no baseline,
/// so it establishes one rather than reporting every contact on the device as
/// newly added -- is tested without `CNContactStore` at all.
enum ContactIdentifierDiff {
    static func added(current: Set<String>, knownBefore: Set<String>?) -> Set<String> {
        guard let knownBefore else { return [] }
        return current.subtracting(knownBefore)
    }
}

/// The one quiet suggestion a foreground check can make: somebody who landed
/// in the address book since last time, is not already in Haven, has a way to
/// reach them, and has not already been asked about and turned down.
///
/// Pure: takes the dismissal check as a closure rather than depending on
/// `ContactChangeState` directly, so picking is tested without touching
/// `UserDefaults` at all.
enum ContactSuggestion {
    /// At most one contact, in the order the address book reported them.
    /// "At most one" is the product rule, not an optimization: a foreground
    /// that surfaced every new contact at once would be the opposite of
    /// quiet.
    static func pick(
        from added: [AddressBookContact],
        mirror: DirectoryMirror?,
        isDismissed: (String) -> Bool
    ) -> AddressBookContact? {
        added.first { contact in
            !isDismissed(contact.id)
                && !contact.name.trimmedLikeJS.isEmpty
                && ContactImportMatching.handle(for: contact) != nil
                && ContactImportMatching.alreadyInHaven(contact, mirror: mirror) == nil
        }
    }
}
