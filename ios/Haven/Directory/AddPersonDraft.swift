import Foundation

/// A way to reach somebody you saved by hand.
///
/// Longer than the four your own card offers, and that asymmetry is the spec's
/// rather than an oversight: your card is an identity you publish, while this
/// is a note about how you actually reach one person, "WhatsApp and Telegram
/// included" (`mvp-design.md`). The raw values are what the server stores and
/// dedups on, so they are lowercase and do not change.
enum AddPersonPlatform: String, CaseIterable, Identifiable, Equatable, Sendable {
    case instagram
    case x
    case linkedin
    case phone
    case whatsapp
    case telegram

    var id: String { rawValue }

    /// What the platform is called in the interface. Text rather than a mark:
    /// the brand glyphs are third-party trademarks with their own usage rules.
    var label: String {
        switch self {
        case .instagram: return "Instagram"
        case .x: return "X"
        case .linkedin: return "LinkedIn"
        case .phone: return "Phone"
        case .whatsapp: return "WhatsApp"
        case .telegram: return "Telegram"
        }
    }

    /// Whether this handle is a phone number, which decides the keyboard and
    /// the autofill hint the field asks for.
    var isPhoneNumber: Bool {
        self == .phone || self == .whatsapp
    }

    var placeholder: String {
        isPhoneNumber ? "Their number" : "Paste a link or type the handle"
    }

    /// The value as it will be stored, or nil while there is not a usable one
    /// -- which is what holds Save disabled.
    ///
    /// Every rule here already existed for the contact question, because a
    /// handle is a fact about a platform and not about which screen asked for
    /// it.
    func parse(_ raw: String) -> String? {
        switch self {
        case .instagram: return ContactValue.instagramHandle(from: raw)
        case .x: return ContactValue.xHandle(from: raw)
        case .linkedin: return ContactValue.linkedInHandle(from: raw)
        case .phone, .whatsapp: return ContactValue.phoneNumber(from: raw)
        case .telegram: return ContactValue.telegramHandle(from: raw)
        }
    }

    /// The page this handle points at, or "" when the platform has no web
    /// profile to point at.
    ///
    /// The server keeps it as the person's `link` and never overwrites one, so
    /// this is the one chance a hand-typed person gets a way back to the
    /// profile they came from. A phone number is not an address, and WhatsApp's
    /// is the number without its plus.
    func profileUrl(for value: String) -> String {
        switch self {
        case .instagram: return "https://instagram.com/\(value)"
        case .x: return "https://x.com/\(value)"
        case .linkedin: return "https://linkedin.com/in/\(value)"
        case .telegram: return "https://t.me/\(value)"
        case .whatsapp: return "https://wa.me/\(value.drop { $0 == "+" })"
        case .phone: return ""
        }
    }

    /// How the stored value reads back to the person typing it: the address it
    /// points at, or the number itself. The same shape the card uses, and for
    /// the same reason -- without a brand glyph, an address is what says which
    /// platform this is.
    func display(_ value: String) -> String {
        switch self {
        case .instagram: return "instagram.com/\(value)"
        case .x: return "x.com/\(value)"
        case .linkedin: return "linkedin.com/in/\(value)"
        case .telegram: return "t.me/\(value)"
        case .phone, .whatsapp: return value
        }
    }
}

/// Everything the add-someone sheet holds, with no UI attached.
///
/// Here rather than in the view because every rule below is a decision worth
/// testing, and because the pin walkthrough runs the same save on a practice
/// capture.
struct AddPersonDraft: Equatable {
    var name = ""
    /// Instagram first because it is the platform people actually swap in
    /// person, and the one the share extension sees most.
    var platform: AddPersonPlatform = .instagram
    var handleText = ""
    var note = ""

    /// The handle as it will be stored, or nil while there is not a usable one.
    var handle: String? { platform.parse(handleText) }

    /// Whether there is enough here to save.
    ///
    /// All three, which is a stricter bar than a share gets. A share arrives
    /// with an account already proven and a person half-distracted; this is
    /// somebody sitting down to write a person out, and the two fields that
    /// make them findable later are the handle, which is identity, and the
    /// note, which is the only part no machine could have filled. A row with
    /// neither is one nobody ever retrieves. It is the same bar
    /// `people:addPerson` sets on the server.
    var canSave: Bool {
        !name.trimmedLikeJS.isEmpty && handle != nil && !note.trimmedLikeJS.isEmpty
    }

    /// Who in the directory already holds this account.
    ///
    /// The one question the mirror answers with confidence, because the server
    /// keys on exactly this pair. Saving onto them is not a mistake to prevent:
    /// the note lands on the person who is already there, which is what the
    /// server does with a re-share.
    func alreadyKnown(in mirror: DirectoryMirror?) -> MirrorPerson? {
        guard let handle else { return nil }
        return mirror?.person(holding: platform.rawValue, value: handle)
    }

    /// Who else is stored under this name.
    ///
    /// Offered, never applied: a name is not a unique key and two people really
    /// can share one. Nobody is offered once the account itself is on file,
    /// because the server has already decided who this is.
    func nameMatches(in mirror: DirectoryMirror?) -> [MirrorPerson] {
        guard alreadyKnown(in: mirror) == nil else { return [] }
        return mirror?.people(named: name) ?? []
    }

    /// The capture to queue, or nil when there is not one worth queueing.
    ///
    /// Nil rather than a capture missing a field: the server refuses those, so
    /// a queued one could never drain and would retry for the life of the
    /// install with nobody ever told.
    func capture(
        attachTo: MirrorPerson? = nil,
        id: UUID = UUID(),
        capturedAt: Date = Date()
    ) -> QueuedCapture? {
        let name = name.trimmedLikeJS
        let note = note.trimmedLikeJS
        guard !name.isEmpty, !note.isEmpty, let handle else { return nil }
        return QueuedCapture(
            id: id,
            capturedAt: capturedAt,
            payload: .manual(
                QueuedCapture.Manual(
                    name: name,
                    platform: platform.rawValue,
                    handleValue: handle,
                    profileUrl: platform.profileUrl(for: handle),
                    note: note,
                    attachToPersonId: attachTo?.id
                )
            )
        )
    }
}
