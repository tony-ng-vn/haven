import ClerkKit
import SwiftUI

/// Onboarding question 3. Skippable, and the one most worth answering: a card
/// nobody can act on is a card that does nothing.
///
/// Every social row starts the same way, by authorizing. What comes back differs
/// per platform, so the flow degrades in steps and each step only appears after
/// the one above it falls short. No row ever advertises a paste field.
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
            actions: { actions }
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
            if let connectFailure {
                Text(connectFailure)
                    .havenBody()
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .havenAnimation(HavenMotion.screen, value: entry)
    }

    private func row(_ platform: ContactPlatform) -> some View {
        let value = chosen?.platform == platform.id ? chosen?.value : nil
        return HavenRow(
            title: platform.title,
            detail: value.map { platform.prefix + $0 },
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
        return "\(platform.title), \(platform.prefix)\(value), primary"
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
                Text(entry.prefix + chosen.value).havenSecondary()
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
                switch entry {
                case .typePhone:
                    // Formatted while the number grows and left alone while it
                    // shrinks: re-adding a space someone just deleted makes
                    // backspace look broken.
                    entryText = typed.count > entryText.count
                        ? ContactValue.formattingPhone(typed)
                        : typed
                    chosen = ContactValue.phoneNumber(from: entryText).map {
                        ChosenContact(platform: .phone, value: $0, verified: false)
                    }
                case .pasteInstagram:
                    entryText = typed
                    chosen = ContactValue.instagramHandle(from: typed).map {
                        ChosenContact(platform: .instagram, value: $0, verified: false)
                    }
                case .confirmLinkedIn:
                    entryText = typed
                    chosen = ContactValue.linkedInHandle(from: typed).map {
                        ChosenContact(platform: .linkedin, value: $0, verified: false)
                    }
                }
            }
        )
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            if let failure = model.failure {
                Text(failure)
                    .havenBody()
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            PrimaryButton(title: "Continue", isLoading: model.isSaving, action: commit)
                .disabled(chosen == nil || connecting != nil)
            GhostButton(title: "Skip for now") { model.skip(.contact) }
                .disabled(model.isSaving || connecting != nil)
        }
        .havenAnimation(HavenMotion.screen, value: model.failure)
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
        case .authorize(let provider):
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
            connectFailure = "\(platform.title) did not connect. Try again, or use another way."
        }
    }

    private func finish(_ platform: ContactPlatform, _ account: ConnectedAccount) {
        // The best case: the handle came back with the token, so the value is
        // proven and nothing else is asked.
        if let username = account.username, !username.isEmpty {
            chosen = ChosenContact(platform: platform.id, value: username, verified: true)
            entry = nil
            return
        }

        guard platform.id == .linkedin else {
            connectFailure = "\(platform.title) did not send a handle. Try another way."
            return
        }
        // Connected and verified, but the address is not in the payload. Our
        // best guess goes in prefilled, so this reads as a confirmation rather
        // than another question.
        let name = account.fullName.isEmpty ? (model.card?.name ?? "") : account.fullName
        let slug = ContactValue.linkedInSlug(from: name)
        entryText = slug
        entry = .confirmLinkedIn(connectedAs: name.isEmpty ? "you" : name)
        chosen = slug.isEmpty
            ? nil
            : ChosenContact(platform: .linkedin, value: slug, verified: false)
    }

    private func commit() {
        guard let chosen else { return }
        Task { await model.saveContact(chosen) }
    }
}

// MARK: - The four ways to be reached

/// How a row gets its value.
private enum ContactMethod {
    /// Authorize, and take whatever the provider sends back.
    case authorize(OAuthProvider)
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
    /// Shown in front of the value, so a row reads as an address rather than a
    /// fragment.
    let prefix: String

    static let x = ContactPlatform(
        id: .x, title: "X", call: "Connect",
        method: .authorize(.x), prefix: "@"
    )
    // The OIDC provider, not the legacy one: Clerk's `oauth_linkedin` is
    // retired and only `oauth_linkedin_oidc` is issued to new instances.
    static let linkedin = ContactPlatform(
        id: .linkedin, title: "LinkedIn", call: "Connect",
        method: .authorize(.linkedinOidc), prefix: "linkedin.com/in/"
    )
    // Typed rather than authorized, because there is nothing to authorize
    // against: Instagram's personal-account API shut down in December 2024 and
    // the replacement covers Creator and Business accounts only, so Clerk
    // offers no Instagram connection at all. Attempting one first would fail
    // for everybody and land here anyway, one wasted round trip later.
    static let instagram = ContactPlatform(
        id: .instagram, title: "Instagram", call: "Add",
        method: .typed(.pasteInstagram), prefix: "@"
    )
    static let phone = ContactPlatform(
        id: .phone, title: "Phone", call: "Add",
        method: .typed(.typePhone), prefix: ""
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
    case pasteInstagram
    case typePhone

    var platform: MyCard.Platform {
        switch self {
        case .confirmLinkedIn: return .linkedin
        case .pasteInstagram: return .instagram
        case .typePhone: return .phone
        }
    }

    /// Nil where the field speaks for itself. Phone needs no explanation;
    /// the other two are explaining a platform's limit, not ours.
    var note: String? {
        switch self {
        case .confirmLinkedIn(let name):
            return """
                Connected as \(name). LinkedIn verifies you but never sends your \
                profile address, so check this is right.
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
        case .pasteInstagram: return "Your Instagram link"
        case .typePhone: return "Your phone number"
        }
    }

    var placeholder: String {
        switch self {
        case .confirmLinkedIn: return "linkedin.com/in/handle"
        case .pasteInstagram: return "Paste your Instagram link"
        case .typePhone: return "Phone number"
        }
    }

    var prefix: String {
        switch self {
        case .confirmLinkedIn: return "linkedin.com/in/"
        case .pasteInstagram: return "instagram.com/"
        case .typePhone: return ""
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .typePhone: return .phonePad
        case .confirmLinkedIn, .pasteInstagram: return .URL
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
