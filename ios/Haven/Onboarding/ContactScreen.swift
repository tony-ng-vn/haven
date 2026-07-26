import ClerkKit
import SwiftUI

/// Onboarding question 3. Skippable, and the one most worth answering: a card
/// nobody can act on is a card that does nothing.
///
/// Every connectable row starts the same way, by authorizing. What comes back
/// differs per platform, so the flow degrades in steps and each step only
/// appears after the one above it falls short. No row ever advertises a paste
/// field, and no row ever dead-ends.
struct ContactScreen: View {
    @ObservedObject var model: OnboardingModel

    @State private var chosen: ChosenContact?
    @State private var connecting: MyCard.Platform?
    @State private var entry: ContactEntry?
    @State private var entryText = ""
    @State private var connectFailure: String?

    var body: some View {
        HavenScreen(
            sky: model.sky,
            litMajors: model.litMajors,
            // A panel opens under the rows. Centred, opening it would shift
            // every row the person was just reading.
            contentAlignment: .top,
            header: {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingStepper(step: .contact)
                    QuestionHeader(
                        question: "How should people reach you?",
                        hint: "Connect an account and we fill in the rest. We never post."
                    )
                }
            },
            content: { rows },
            actions: {
                OnboardingActions(
                    failure: model.failure ?? connectFailure,
                    isSaving: model.isSaving,
                    canContinue: chosen != nil && connecting == nil,
                    onContinue: commit,
                    onSkip: { model.skip(.contact) },
                    canSkip: connecting == nil
                )
            }
        )
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connect an account").havenGroupLabel().padding(.bottom, 5)
            ForEach(ContactPlatform.connectable, id: \.id) { row($0) }
            Text("Or type one").havenGroupLabel()
                .padding(.top, 15)
                .padding(.bottom, 5)
            ForEach(ContactPlatform.typeable, id: \.id) { row($0) }
            if let entry {
                panel(entry)
                    .padding(.top, 14)
                    // A new panel is a new field, so switching rows focuses the
                    // one that just opened rather than leaving the old one's
                    // keyboard up over a field nobody asked for.
                    .id(entry)
            }
        }
        .havenAnimation(HavenMotion.screen, value: entry)
    }

    private func row(_ platform: ContactPlatform) -> some View {
        let value = chosen?.platform == platform.id ? chosen?.value : nil
        return HavenRow(
            title: platform.title,
            detail: value.map { platform.handlePrefix + $0 },
            accessibilityText: spoken(platform, value),
            action: { choose(platform) }
        ) {
            if connecting == platform.id {
                ProgressView().controlSize(.small).tint(HavenColor.faint)
            } else if value != nil {
                RowAccessory(text: "Primary", isSet: true)
            } else {
                RowAccessory(text: platform.call)
            }
        }
    }

    private func spoken(_ platform: ContactPlatform, _ value: String?) -> String {
        if connecting == platform.id { return "\(platform.title), connecting" }
        guard let value else { return "\(platform.title), \(platform.call)" }
        return "\(platform.title), \(platform.handlePrefix)\(value), primary"
    }

    // MARK: - The extra step, when there is one

    @ViewBuilder
    private func panel(_ entry: ContactEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = entry.note {
                Text(note).havenHint()
            }
            HavenField(
                label: entry.label,
                placeholder: entry.placeholder,
                text: typing,
                keyboard: entry.keyboard,
                capitalization: .never,
                autofocus: true,
                onSubmit: commit
            )
            if let chosen, chosen.platform == entry.platform {
                // A live preview of what the card will carry, so a paste that
                // was reduced to a handle is visibly the right handle.
                Text(entry.addressPrefix + chosen.value).havenSecondary()
            }
        }
    }

    /// Every keystroke re-derives the contact, so Continue is enabled by the
    /// value being usable rather than by the field merely being non-empty.
    private var typing: Binding<String> {
        Binding(
            get: { entryText },
            set: { typed in
                guard let entry else { return }
                // A phone number is formatted while it grows and left alone
                // while it shrinks: re-adding a space someone just deleted
                // makes backspace look broken.
                entryText = entry == .typePhone && typed.count > entryText.count
                    ? ContactValue.formattingPhone(typed)
                    : typed
                chosen = entry.parse(entryText)
            }
        )
    }

    // MARK: - Behaviour

    private func choose(_ platform: ContactPlatform) {
        guard connecting == nil, !model.isSaving else { return }
        connectFailure = nil
        // Tapping the row that is already answered, or whose panel is already
        // open, is not a request to start over.
        guard chosen?.platform != platform.id, entry?.platform != platform.id else { return }

        switch platform.method {
        case .typed(let panel):
            chosen = nil
            entryText = ""
            entry = panel
        case .authorize(let provider, _, _):
            Task { await connect(platform, provider: provider) }
        }
    }

    private func connect(_ platform: ContactPlatform, provider: OAuthProvider) async {
        chosen = nil
        entry = nil
        connecting = platform.id
        defer { connecting = nil }
        do {
            finish(platform, try await ContactConnector.connect(provider))
        } catch ContactConnectError.cancelled {
            // Nothing to report: backing out of the provider's page is a choice.
        } catch {
            // Not a dead end. A platform that will not tell us who you are there
            // is a reason to ask you instead, and it is the same panel the
            // no-handle case opens.
            connectFailure = "\(platform.title) did not connect. Fill it in here instead."
            degrade(platform, to: model.card?.name ?? "you")
        }
    }

    private func finish(_ platform: ContactPlatform, _ account: ConnectedAccount) {
        guard case .authorize(_, let provesItsHandle, _) = platform.method else { return }

        // Whether a username in the payload IS the handle is a fact about the
        // platform, not about whether one happened to arrive. LinkedIn's
        // payload can carry a username that is not the profile address, and
        // taking it would store an unproven handle as verified and skip the
        // panel that exists to check it.
        if provesItsHandle, let username = account.username, !username.isEmpty {
            chosen = ChosenContact(platform: platform.id, value: username, verified: true)
            entry = nil
            return
        }
        degrade(platform, to: account.fullName.isEmpty ? (model.card?.name ?? "you") : account.fullName)
    }

    /// Opens the platform's panel, prefilled with whatever a first guess can be
    /// made from. The one landing for both a payload without a handle and an
    /// authorization that never got there.
    private func degrade(_ platform: ContactPlatform, to name: String) {
        guard case .authorize(_, _, let fallback) = platform.method else { return }
        let panel = fallback(name)
        entryText = panel.guess(from: name)
        entry = panel
        chosen = panel.parse(entryText)
    }

    private func commit() {
        guard let chosen else { return }
        Task { await model.saveContact(chosen) }
    }
}

// MARK: - The four ways to be reached

/// How a row gets its value.
private enum ContactMethod {
    /// Authorize.
    ///
    /// `provesItsHandle` says whether a username in the payload may be trusted
    /// as the handle. `fallback` is where the row lands when no trusted handle
    /// comes back, and every connectable row has one: a platform that will not
    /// tell us who you are there is a reason to ask, never a dead end. It is
    /// given the person's name, which is all a first guess has to work with.
    case authorize(OAuthProvider, provesItsHandle: Bool, fallback: (String) -> ContactEntry)
    /// Supplied by hand, because there is nothing to authorize against.
    case typed(ContactEntry)
}

/// One row of the contact question.
private struct ContactPlatform {
    let id: MyCard.Platform
    let title: String
    /// What the row invites you to do while it is empty.
    let call: String
    let method: ContactMethod
    /// Shown in front of the value on the row, so it reads as a handle rather
    /// than a fragment. The panel's live preview uses the fuller
    /// `ContactEntry.addressPrefix` instead.
    let handlePrefix: String

    static let x = ContactPlatform(
        id: .x, title: "X", call: "Connect",
        // X sends the username with the token, so the value is proven. That
        // read sits behind paid API tiers, so the day it stops arriving the row
        // degrades to a paste rather than dead-ending.
        method: .authorize(.x, provesItsHandle: true, fallback: { _ in .pasteX }),
        handlePrefix: "@"
    )
    // The OIDC provider, not the legacy one: Clerk's `oauth_linkedin` is
    // retired and only `oauth_linkedin_oidc` is issued to new instances.
    static let linkedin = ContactPlatform(
        id: .linkedin, title: "LinkedIn", call: "Connect",
        // LinkedIn proves the person and never sends the profile address, so a
        // username in its payload is not the handle and is never taken for one.
        method: .authorize(
            .linkedinOidc,
            provesItsHandle: false,
            fallback: { .confirmLinkedIn(connectedAs: $0) }
        ),
        handlePrefix: "linkedin.com/in/"
    )
    // Typed rather than authorized, because there is nothing to authorize
    // against: Instagram's personal-account API shut down in December 2024 and
    // the replacement covers Creator and Business accounts only, so Clerk
    // offers no Instagram connection at all. Attempting one first would fail
    // for everybody and land here anyway, one wasted round trip later.
    static let instagram = ContactPlatform(
        id: .instagram, title: "Instagram", call: "Add",
        method: .typed(.pasteInstagram), handlePrefix: "@"
    )
    static let phone = ContactPlatform(
        id: .phone, title: "Phone", call: "Add",
        method: .typed(.typePhone), handlePrefix: ""
    )

    /// The rows that authorize, and the rows that do not. The split is the
    /// question's two groups, and it is a fact about the platforms rather than a
    /// layout choice.
    static let connectable = [x, linkedin]
    static let typeable = [instagram, phone]
}

/// What the chosen platform still needs from the person.
///
/// One at a time: two open panels would be two questions, and this screen asks
/// one.
private enum ContactEntry: Hashable {
    case confirmLinkedIn(connectedAs: String)
    case pasteX
    case pasteInstagram
    case typePhone

    var platform: MyCard.Platform {
        switch self {
        case .confirmLinkedIn: return .linkedin
        case .pasteX: return .x
        case .pasteInstagram: return .instagram
        case .typePhone: return .phone
        }
    }

    /// What the panel makes of what is in its field, or nil while there is
    /// nothing usable yet, which is what keeps Continue disabled.
    ///
    /// Never `verified`: a value that had to be typed or confirmed was, by
    /// definition, not proven by the platform.
    func parse(_ typed: String) -> ChosenContact? {
        let value: String?
        switch self {
        case .confirmLinkedIn: value = ContactValue.linkedInHandle(from: typed)
        case .pasteX: value = ContactValue.xHandle(from: typed)
        case .pasteInstagram: value = ContactValue.instagramHandle(from: typed)
        case .typePhone: value = ContactValue.phoneNumber(from: typed)
        }
        return value.map { ChosenContact(platform: platform, value: $0, verified: false) }
    }

    /// What the field starts with. Only LinkedIn has anything to guess from: a
    /// slug built out of the name it just proved, which the panel exists to have
    /// corrected. Wrong is fine; empty is worse.
    func guess(from name: String) -> String {
        switch self {
        case .confirmLinkedIn: return ContactValue.linkedInSlug(from: name)
        case .pasteX, .pasteInstagram, .typePhone: return ""
        }
    }

    /// Nil where the field speaks for itself. Phone needs no explanation; the
    /// others are explaining a platform's limit, not ours.
    var note: String? {
        switch self {
        case .confirmLinkedIn(let name):
            return """
                Connected as \(name). LinkedIn verifies you but never sends your \
                profile address, so check this is right.
                """
        case .pasteX:
            return """
                X only shares usernames with apps on paid API tiers, so paste \
                your link and we will pull the handle out of it.
                """
        case .pasteInstagram:
            return """
                Instagram only shares profiles with apps for Creator and Business \
                accounts, so paste your link and we will pull the handle out of it.
                """
        case .typePhone:
            return nil
        }
    }

    var label: String {
        switch self {
        case .confirmLinkedIn: return "Your LinkedIn address"
        case .pasteX: return "Your X link"
        case .pasteInstagram: return "Your Instagram link"
        case .typePhone: return "Your phone number"
        }
    }

    var placeholder: String {
        switch self {
        case .confirmLinkedIn: return "linkedin.com/in/handle"
        case .pasteX: return "Paste your X link"
        case .pasteInstagram: return "Paste your Instagram link"
        case .typePhone: return "Phone number"
        }
    }

    /// The address the card will carry, shown live under the field.
    var addressPrefix: String {
        switch self {
        case .confirmLinkedIn: return "linkedin.com/in/"
        case .pasteX: return "x.com/"
        case .pasteInstagram: return "instagram.com/"
        case .typePhone: return ""
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .typePhone: return .phonePad
        case .confirmLinkedIn, .pasteX, .pasteInstagram: return .URL
        }
    }
}

// MARK: - Previews

@MainActor
private func previewModel() -> OnboardingModel {
    OnboardingModel(
        previewUserId: "user_2abcDEF123",
        card: MyCard(
            username: "tony",
            name: "Tony Nguyen",
            city: MyCard.City(name: "Ho Chi Minh City", country: "Vietnam")
        )
    )
}

#Preview("Contact") {
    ContactScreen(model: previewModel())
}

#Preview("Contact, accessibility XXXL") {
    ContactScreen(model: previewModel())
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Contact, Reduce Motion") {
    ContactScreen(model: previewModel())
        .havenReduceMotion()
}
