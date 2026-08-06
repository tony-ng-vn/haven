import Foundation

/// The one handle an address-book contact would be imported under.
enum ContactHandle: Equatable, Sendable {
    case phone(String)
    case email(String)
}

/// Turns a device contact into the same decisions `VCardContact` and
/// `ShareSubject` already make for a shared card: phone over email, dedup
/// against the mirror, and the `.manual` capture the drain already knows how
/// to send. Pure and offline, so it is tested without `CNContactStore` at all
/// -- see `AddressBookProviding` for where the framework itself lives.
enum ContactImportMatching {
    /// The one handle an import would save this contact under, or nil when
    /// the card has neither a phone nor an email -- the same "nothing to key
    /// on" rule a shared vCard with neither is refused under.
    static func handle(for contact: AddressBookContact) -> ContactHandle? {
        if let phone = contact.phones.first { return .phone(phone) }
        if let email = contact.emails.first { return .email(email) }
        return nil
    }

    /// Who in the mirror already holds this contact's phone or email, if
    /// anybody.
    ///
    /// Phones are folded through the same normalization `ConvexCaptureSink`
    /// applies at drain time before comparing, so a contact whose number
    /// differs from what is on file only in formatting -- spaces, a missing
    /// country code the device fills in locally -- still reads as covered,
    /// not as a second row for the same person.
    static func alreadyInHaven(_ contact: AddressBookContact, mirror: DirectoryMirror?) -> MirrorPerson? {
        guard let mirror else { return nil }
        for raw in contact.phones {
            let normalized = ContactValue.normalizedOrRaw(phone: raw)
            if let person = mirror.person(holding: "phone", value: normalized) { return person }
        }
        for email in contact.emails {
            if let person = mirror.person(holding: "email", value: email) { return person }
        }
        return nil
    }

    /// The device contacts worth offering as an import row: a name, a handle
    /// to save them under, and nobody in the mirror covering them already.
    ///
    /// This is the dedup display rule: a contact the mirror already covers is
    /// not a distinct row at all, because the Haven person already shown for
    /// that match covers them.
    static func importCandidates(
        from contacts: [AddressBookContact], mirror: DirectoryMirror?
    ) -> [AddressBookContact] {
        contacts.filter { contact in
            !contact.name.trimmedLikeJS.isEmpty
                && handle(for: contact) != nil
                && alreadyInHaven(contact, mirror: mirror) == nil
        }
    }

    /// The capture a one-tap import queues, or nil when there is nothing to
    /// save this person under.
    ///
    /// Reuses the same `.manual` payload a shared vCard already writes
    /// through: no note (this is a tap, not a form), no web profile, and a
    /// phone left raw exactly the way a card's phone is -- `ConvexCaptureSink`
    /// normalizes it at drain time, the one place in the pipeline with
    /// PhoneNumberKit.
    static func capture(
        for contact: AddressBookContact, id: UUID = UUID(), capturedAt: Date = Date()
    ) -> QueuedCapture? {
        guard let handle = handle(for: contact) else { return nil }
        let name = contact.name.trimmedLikeJS
        guard !name.isEmpty else { return nil }
        let platform: String
        let value: String
        switch handle {
        case .phone(let raw):
            platform = "phone"
            value = raw
        case .email(let raw):
            platform = "email"
            value = raw
        }
        return QueuedCapture(
            id: id,
            capturedAt: capturedAt,
            payload: .manual(
                QueuedCapture.Manual(
                    name: name,
                    platform: platform,
                    handleValue: value,
                    profileUrl: "",
                    note: nil,
                    attachToPersonId: nil,
                    source: "imported"
                )
            )
        )
    }
}

extension DirectoryMirror {
    /// Every phone and email this account already holds, folded the same way
    /// a stored handle is.
    ///
    /// For `ContactAccessButton`'s `ignoredPhoneNumbers`/`ignoredEmails`: the
    /// button does its own matching over contacts Haven cannot otherwise see,
    /// and without this it would offer to reveal somebody already on file as
    /// though they were new.
    var knownPhonesAndEmails: (phones: Set<String>, emails: Set<String>) {
        var phones: Set<String> = []
        var emails: Set<String> = []
        for person in people {
            for handle in person.handles {
                switch handle.platform.trimmedLikeJS.lowercased() {
                case "phone": phones.insert(handle.value)
                case "email": emails.insert(handle.value)
                default: break
                }
            }
        }
        return (phones, emails)
    }
}
