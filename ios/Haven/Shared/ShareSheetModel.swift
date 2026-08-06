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
    /// A contact shared from Apple's Contacts app (or a .vcf from Files):
    /// the name on the card, plus the one handle it saves against. Reuses
    /// `people:saveSharedProfile` through the `.manual` capture the way a
    /// hand-typed WhatsApp or Telegram add already does -- a phone or an
    /// email is not one of the three platforms `ProfileLink` names, but the
    /// mutation was always keyed on a free-form platform string, not on
    /// `SharedPlatform`.
    case contact(name: String, platform: String, handleValue: String)

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

    /// The profile link embedded somewhere in a free-form share message, or
    /// nil when none of it is one.
    ///
    /// LinkedIn's own app proved, on device, that it shares a profile as a
    /// sentence with the link inside it ("Tony Nguyen sent you this LinkedIn
    /// link: https://www.linkedin.com/in/tony-buildd"), not as a URL
    /// attachment -- `ShareInput` in the extension hands the whole message
    /// here rather than trying to find the link itself, because deciding
    /// what counts as a profile link is `sharedURL`'s job already and a
    /// second decider is a second place for the two to disagree.
    ///
    /// The whole trimmed message is tried first, which is what accepts a bare
    /// scheme-less handle shared on a line by itself the same way `sharedURL`
    /// already does. Failing that, every whitespace-separated word is offered
    /// in turn, stripped of sentence punctuation it is not part of -- a
    /// trailing period after "tony-buildd." is the sentence ending, not the
    /// handle, and left on it would silently save the wrong one rather than
    /// fail to parse at all.
    init?(embeddedInText text: String) {
        let trimmed = text.trimmedLikeJS
        guard !trimmed.isEmpty else { return nil }
        if let whole = ShareSubject(sharedURL: trimmed) {
            self = whole
            return
        }
        for word in trimmed.split(whereSeparator: \.isJSWhitespace) {
            let candidate = Self.strippingTrailingPunctuation(String(word))
            if let found = ShareSubject(sharedURL: candidate) {
                self = found
                return
            }
        }
        return nil
    }

    /// Reads a shared Contacts card, or nil when it names nobody, or names
    /// somebody with neither a phone nor an email to save them under.
    ///
    /// `saveSharedProfile` dedups on a handle; a name with no way to reach
    /// them can never drain, so it is not a subject any more than an
    /// unrecognized URL is.
    ///
    /// Phone wins over email when a card carries both: it is the stronger
    /// key, less likely to be entered two different ways by two different
    /// apps than an email address is -- `VCardContact` owns the extraction,
    /// this owns deciding which of what it found is worth keying on.
    init?(vCard data: Data) {
        guard let parsed = VCardContact.parse(data) else { return nil }
        if let phone = parsed.phone {
            self = .contact(name: parsed.name, platform: "phone", handleValue: phone)
        } else if let email = parsed.email {
            self = .contact(name: parsed.name, platform: "email", handleValue: email)
        } else {
            return nil
        }
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

    /// Sentence punctuation a word can trail without being part of a link:
    /// "...tony-buildd." ends in a period that belongs to the sentence.
    /// Never a leading strip -- nothing a person writes puts punctuation in
    /// front of a link the way a sentence puts it after one.
    private static func strippingTrailingPunctuation(_ word: String) -> String {
        let punctuation: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}", "'", "\""]
        var trimmed = Substring(word)
        while let last = trimmed.last, punctuation.contains(last) {
            trimmed.removeLast()
        }
        return String(trimmed)
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
        switch subject {
        case .profile(let link, _):
            return mirror?.person(holding: link)
        case .contact(_, let platform, let handleValue):
            return mirror?.person(holding: platform, value: handleValue)
        case .screenshot:
            return nil
        }
    }

    /// What the name field starts with.
    ///
    /// A confirmation, never automation. Only a LinkedIn slug carries a name
    /// worth confirming; Instagram and X hand over a handle, and a field
    /// prefilled with a handle looks like a name without being one -- a fast
    /// tap-through would save a person named after their account. The handle
    /// goes in `identityLine` instead, where it is true. A contact card is
    /// the one subject that carries an actual name rather than a guess or a
    /// handle, and it fills the field for the same reason `alreadyKnown`
    /// does below: editable, never automated past the point of a glance.
    ///
    /// Re-examined in wave G4 and left exactly as PR 129 shipped it. The case
    /// for prefilling is that most people's Instagram handle is close to their
    /// name; the case against is the one that decides it -- a field prefilled
    /// with a handle looks like a name without being one, and the whole point
    /// of the sheet is that it is answered in two seconds by somebody
    /// mid-conversation. The fast tap-through is the normal path, not the
    /// careless one.
    var namePrefill: String {
        if let known = alreadyKnown { return known.name }
        switch subject {
        case .profile(let link, _) where link.platform == .linkedin:
            return ProfileURL.nameGuess(fromSlug: link.handle)
        case .contact(let name, _, _):
            return name
        default:
            return ""
        }
    }

    /// The line under the name field: the account, which is the part that is
    /// known rather than guessed.
    ///
    /// A LinkedIn slug is not a handle anyone recognizes, so it reads as the
    /// URL it is. A contact card's handle is a phone or an email; either
    /// already reads as itself.
    var identityLine: String? {
        switch subject {
        case .profile(let link, _):
            switch link.platform {
            case .linkedin: return "linkedin.com/in/\(link.handle)"
            case .instagram, .x: return "@\(link.handle) on \(link.platform.displayName)"
            }
        case .contact(_, _, let handleValue):
            return handleValue
        case .screenshot:
            return nil
        }
    }

    /// Who the guessed name might already be.
    ///
    /// A suggestion, offered rather than applied: a name is not a unique key,
    /// and Haven never decides two people are one. Nobody is suggested when
    /// the account is already on file -- offering to attach somebody to
    /// themselves is noise.
    ///
    /// A LinkedIn share folds the name through the same close-match machinery
    /// `AddPersonSheet` uses (`NameSuggestion`, see Brief 3) -- a re-shared
    /// profile with a new slug is exactly the "typed a name that is already
    /// in the directory" case, just typed by whoever re-shared it rather than
    /// by the user, and it is the one platform Haven cannot reopen on a
    /// rename (`PersonReach.openURL`), so catching the same person under a
    /// changed slug is worth a fuzzy match. A contact card keeps the exact
    /// fold: a card's name is the one Apple has on file, not somebody's guess
    /// at a slug, and widening it to fuzzy would offer strangers who merely
    /// sound alike.
    var nameMatches: [MirrorPerson] {
        guard alreadyKnown == nil, !namePrefill.isEmpty else { return [] }
        guard let mirror else { return [] }
        if isLinkRefreshOffer {
            return mirror.nameSuggestions(for: namePrefill).map(\.person)
        }
        return mirror.people(named: namePrefill)
    }

    /// Whether the "same person?" offer above is a LinkedIn link refresh.
    ///
    /// It reads differently from the generic offer -- not "is this the same
    /// person", but "this looks like a new link for somebody already saved" --
    /// because a LinkedIn slug is the one profile URL that changes on its own
    /// when somebody renames.
    var isLinkRefreshOffer: Bool {
        if case .profile(let link, _) = subject { return link.platform == .linkedin }
        return false
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
        case .contact(_, let platform, let handleValue):
            // Reuses `.manual`, the same payload a hand-typed WhatsApp or
            // Telegram add already queues: one platform, one handle, no web
            // profile to point back at.
            payload = .manual(
                QueuedCapture.Manual(
                    name: name,
                    platform: platform,
                    handleValue: handleValue,
                    profileUrl: "",
                    note: note,
                    attachToPersonId: attachTo?.id,
                    source: "imported"
                )
            )
        }
        return QueuedCapture(id: id, capturedAt: capturedAt, payload: payload)
    }
}
