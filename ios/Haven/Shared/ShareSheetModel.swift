import Foundation

extension SharedPlatform {
    /// What the platform is called out loud.
    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .linkedin: return "LinkedIn"
        case .x: return "X"
        }
    }
}

/// What a share handed Haven, once it has been made sense of.
enum ShareSubject: Equatable, Sendable {
    case profile(link: ProfileLink, profileUrl: String)
    /// An image already copied into the App Group container. The extension
    /// never uploads it; the app's drain does.
    case screenshot(fileName: String)

    /// Reads a shared URL, or nil when it is not one person's profile.
    ///
    /// A shared post is content, and saving its author as somebody the user
    /// met would be a lie about where they know them from.
    init?(sharedURL raw: String) {
        guard
            let link = ProfileURL.parse(raw),
            let normalized = ProfileURL.normalize(raw)
        else { return nil }
        self = .profile(link: link, profileUrl: Self.withoutTracking(normalized))
    }

    /// The profile URL without the share sheet's tracking noise (`?s=`,
    /// `?igsh=`, the four `utm_*`), so re-sharing one person twice does not
    /// file two different URLs against them.
    private static func withoutTracking(_ url: String) -> String {
        let stripped = url.prefix { $0 != "?" && $0 != "#" }
        // A trailing slash is the same page, so it is the same link.
        return stripped.count > 1 && stripped.hasSuffix("/")
            ? String(stripped.dropLast()) : String(stripped)
    }
}

/// Every decision the share sheet makes, with no UI attached.
///
/// Lives in Shared rather than the extension because the pin walkthrough runs
/// the same flow inside the app, on a practice capture -- and because the
/// decisions here are the ones worth testing.
struct ShareSheetModel {
    let subject: ShareSubject
    /// The app's last copy of the directory, or nil before it has ever synced.
    /// A cache, never the source of truth.
    let mirror: DirectoryMirror?

    /// Who already holds this account.
    ///
    /// The one question the mirror answers with confidence, because the server
    /// keys on exactly this pair. Then the sheet is not asking who this is, it
    /// is showing who it already is.
    var alreadyKnown: MirrorPerson? {
        guard case .profile(let link, _) = subject else { return nil }
        return mirror?.person(holding: link)
    }

    /// What the name field starts with.
    ///
    /// A confirmation, never automation. Only a LinkedIn slug carries a name
    /// worth confirming; Instagram and X hand over a handle, and a field
    /// prefilled with a handle looks like a name without being one -- a fast
    /// tap-through would save a person named after their account. The handle
    /// goes in `identityLine` instead, where it is true.
    var namePrefill: String {
        if let known = alreadyKnown { return known.name }
        guard case .profile(let link, _) = subject, link.platform == .linkedin else {
            return ""
        }
        return ProfileURL.nameGuess(fromSlug: link.handle)
    }

    /// The line under the name field: the account, which is the part that is
    /// known rather than guessed.
    ///
    /// A LinkedIn slug is not a handle anyone recognizes, so it reads as the
    /// URL it is.
    var identityLine: String? {
        guard case .profile(let link, _) = subject else { return nil }
        switch link.platform {
        case .linkedin: return "linkedin.com/in/\(link.handle)"
        case .instagram, .x: return "@\(link.handle) on \(link.platform.displayName)"
        }
    }

    /// Who the guessed name might already be.
    ///
    /// A suggestion, offered rather than applied: a name is not a unique key,
    /// and Haven never decides two people are one. Nobody is suggested when
    /// the account is already on file -- offering to attach somebody to
    /// themselves is noise.
    var nameMatches: [MirrorPerson] {
        guard alreadyKnown == nil, !namePrefill.isEmpty else { return [] }
        return mirror?.people(named: namePrefill) ?? []
    }

    /// The rest of the directory, for when the guess found nobody.
    func search(_ query: String) -> [MirrorPerson] {
        mirror?.search(query) ?? []
    }

    /// Whether there is enough here to save.
    ///
    /// The name is the one field a person genuinely requires, and the server
    /// refuses a save without one.
    func canSave(name: String) -> Bool {
        !name.trimmedLikeJS.isEmpty
    }

    /// The capture to queue, or nil when there is not one worth queueing.
    ///
    /// Nil rather than a capture with a blank name: the server throws without
    /// one, so a queued capture missing it could never drain. It would retry
    /// forever and nobody would ever be told.
    func capture(
        name: String,
        note: String,
        attachTo: MirrorPerson?,
        id: UUID = UUID(),
        capturedAt: Date = Date()
    ) -> QueuedCapture? {
        let name = name.trimmedLikeJS
        guard !name.isEmpty else { return nil }
        // An empty note is no note, not an empty one -- otherwise the server
        // files a blank line in the person's context.
        let trimmedNote = note.trimmedLikeJS
        let note = trimmedNote.isEmpty ? nil : trimmedNote

        let payload: QueuedCapture.Payload
        switch subject {
        case .profile(let link, let profileUrl):
            payload = .profile(
                QueuedCapture.Profile(
                    link: link,
                    profileUrl: profileUrl,
                    name: name,
                    note: note,
                    attachToPersonId: attachTo?.id
                )
            )
        case .screenshot(let fileName):
            payload = .screenshot(
                QueuedCapture.Screenshot(fileName: fileName, note: note)
            )
        }
        return QueuedCapture(id: id, capturedAt: capturedAt, payload: payload)
    }
}
