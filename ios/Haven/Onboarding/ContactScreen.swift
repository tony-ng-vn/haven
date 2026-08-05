import SwiftUI

/// Onboarding question 3. Skippable, and the one most worth answering: a card
/// nobody can act on is a card that does nothing.
///
/// Every connectable row starts the same way, by authorizing through
/// Composio. What comes back differs per platform, so the flow degrades in
/// steps and each step only appears after the one above it falls short. No
/// row ever advertises a paste field, and no row ever dead-ends.
struct ContactScreen: View {
    @ObservedObject var model: OnboardingModel

    @State private var chosen: ChosenContact?
    @State private var connecting: MyCard.Platform?
    @State private var entry: ContactEntry?
    @State private var entryText = ""
    @State private var connectFailure: String?
    /// The browser page for whichever connection is in flight. Non-nil is
    /// what drives the sheet; set back to nil both when the person taps
    /// Safari's own Done and when polling settles on its own. `cancelPoll`
    /// runs from `onDismiss` either way -- a manual dismiss has to stop the
    /// loop and free `connecting` right away, not up to a poll's own bound
    /// later, and a settled poll has already cleared both itself, so the
    /// second call is a no-op rather than a second ending racing the first.
    @State private var browserURL: URL?
    @State private var pollTask: Task<SocialConnectOutcome, Never>?

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
        .sheet(isPresented: browserPresented, onDismiss: cancelPoll) {
            if let browserURL { SafariPage(url: browserURL) }
        }
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
            // The account-type note, while the row is still empty; the
            // handle, once it is not. Never both -- the note explains a limit
            // that no longer matters once the row shows what it connected.
            detail: value.map { platform.handlePrefix + $0 } ?? platform.subtitle,
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
        guard let value else {
            return [platform.title, platform.subtitle, platform.call]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
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
        case .authorize:
            Task { await connect(platform) }
        }
    }

    private var browserPresented: Binding<Bool> {
        Binding(
            get: { browserURL != nil },
            set: { presented in if !presented { browserURL = nil } }
        )
    }

    /// Stops a poll in progress and frees the row it was holding, the moment
    /// the browser closes -- by hand or on its own. A no-op once a poll has
    /// already settled and cleared `pollTask` itself: `onDismiss` fires for
    /// both endings, and only the first one still has anything to cancel.
    private func cancelPoll() {
        guard pollTask != nil else { return }
        pollTask?.cancel()
        pollTask = nil
        connecting = nil
    }

    private func connect(_ platform: ContactPlatform) async {
        chosen = nil
        entry = nil
        connecting = platform.id
        defer {
            // A newer attempt may already own the row: `cancelPoll` cancels
            // `pollTask` but cannot make `ContactConnector.poll` return
            // early, since it has no cancellation handler of its own, so
            // this `connect` can still be suspended, stale, well after a
            // second tap started its own attempt and reset `connecting`
            // itself. `pollTask` is the shared signal for "something is
            // still legitimately polling" -- nil means nothing is, which is
            // the only time this attempt's own ending is the one that gets
            // to clear the row. Comparing against `platform` instead would
            // not catch the same platform being retried after a cancel,
            // which looks identical from here.
            if pollTask == nil { connecting = nil }
        }

        switch await ContactConnector.initiate(platform.id) {
        case .already(let handle):
            // Composio's own dedupe short-circuits here with no browser trip,
            // and no fresh tool call either -- there is a proven handle but
            // no photo URL to go with it this time.
            finish(platform, handle: handle, photoUrl: nil)
        case .redirect(let url, let connectedAccountId):
            await connectThroughBrowser(platform, url: url, connectedAccountId: connectedAccountId)
        case .unsupportedAccount:
            failToConnect(platform, reason: platform.unsupportedReason)
        case .failed:
            failToConnect(platform, reason: nil)
        }
    }

    /// Opens the browser, polls while it is up, and closes it again once
    /// polling settles -- on a proven handle, a rejection, a failure, or the
    /// person tapping Safari's own Done, which cancels `pollTask` through
    /// `onDismiss` before this ever sees an outcome.
    private func connectThroughBrowser(
        _ platform: ContactPlatform,
        url: URL,
        connectedAccountId: String
    ) async {
        // Belt and suspenders alongside `cancelPoll`: nothing should still be
        // running here, but a leftover task quietly finishing later and
        // calling `finish` for a row nobody is looking at anymore is worse
        // than a redundant cancel of something already gone.
        pollTask?.cancel()
        browserURL = url
        let task = Task { await ContactConnector.poll(platform: platform.id, connectedAccountId: connectedAccountId) }
        pollTask = task
        let outcome = await task.value
        // A newer attempt may have already taken over `pollTask` (and, with
        // it, `connecting` and `browserURL`) while this one was still
        // suspended waiting out `ContactConnector.poll`'s own internal
        // deadline: `cancelPoll` marks a task cancelled but polling has no
        // cancellation handler, so cancelling does not make it return early.
        // `Task` is Equatable by identity, so this is exact: only the
        // attempt that still owns `pollTask` may write the trailing state or
        // act on its outcome. A stale one finishing late is a no-op, not a
        // clobber of whatever the current attempt is doing.
        guard pollTask == task else { return }
        pollTask = nil
        browserURL = nil

        switch outcome {
        case .connected(let handle, let photoUrl):
            finish(platform, handle: handle, photoUrl: photoUrl)
        case .unsupportedAccount:
            failToConnect(platform, reason: platform.unsupportedReason)
        case .failed:
            failToConnect(platform, reason: nil)
        case .cancelled:
            break // Backing out of the browser page is a choice, not a failure.
        }
    }

    /// Every connected outcome now hands back a handle Composio's tool
    /// proved -- LinkedIn's vanityName is as real as X's or Instagram's
    /// username -- so there is nothing left to confirm the way LinkedIn's
    /// Clerk payload once needed. The photo is handed to the model rather
    /// than imported here: it should arrive with the contact answer once
    /// Continue is pressed, not during a panel and a correction that may
    /// follow this same tap.
    private func finish(_ platform: ContactPlatform, handle: String, photoUrl: String?) {
        guard !handle.isEmpty else {
            failToConnect(platform, reason: nil)
            return
        }
        model.rememberAvatar(photoUrl)
        chosen = ChosenContact(platform: platform.id, value: handle, verified: true)
        entry = nil
    }

    /// Opens the platform's fallback panel, prefilled with whatever a first
    /// guess can be made from. The one landing for a declined authorization,
    /// a failed one, and an account Composio's tool cannot read.
    private func failToConnect(_ platform: ContactPlatform, reason: String?) {
        guard case .authorize(let fallback) = platform.method else { return }
        connectFailure = reason ?? "\(platform.title) did not connect. Fill it in here instead."
        let name = model.card?.name ?? "you"
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
    /// Authorize through Composio. `fallback` is where the row lands when the
    /// authorization is declined, fails, or proves an account Composio's tool
    /// cannot read -- every connectable row has one: a platform that will not
    /// connect is a reason to ask, never a dead end. It is given the person's
    /// name, which is all a first guess has to work with.
    case authorize(fallback: (String) -> ContactEntry)
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
    /// A quiet line under the row while it is still empty, for a platform
    /// whose connection has a limit worth knowing before tapping rather than
    /// after. Nil everywhere but Instagram.
    var subtitle: String?
    /// What `connectFailure` says when this platform's own authorization
    /// fails in a way worth naming specifically, rather than the generic
    /// "did not connect." Nil everywhere but Instagram.
    var unsupportedReason: String?

    static let x = ContactPlatform(
        id: .x, title: "X", call: "Connect",
        method: .authorize(fallback: { _ in .enterX }),
        handlePrefix: "@"
    )
    // The OIDC provider naming lived here when this went through Clerk; now
    // every connectable platform goes through the same Composio actions, and
    // there is no per-platform provider to name.
    static let linkedin = ContactPlatform(
        id: .linkedin, title: "LinkedIn", call: "Connect",
        method: .authorize(fallback: { _ in .confirmLinkedIn }),
        handlePrefix: "linkedin.com/in/"
    )
    // Composio's INSTAGRAM_GET_USER_INFO only reads creator and business
    // accounts -- a personal account authorizes fine and then fails to prove
    // a handle, which is what `unsupportedReason` and `subtitle` both name,
    // one before the tap and one after.
    static let instagram = ContactPlatform(
        id: .instagram, title: "Instagram", call: "Connect",
        method: .authorize(fallback: { _ in .enterInstagram }),
        handlePrefix: "@",
        subtitle: "Works with creator and business accounts",
        unsupportedReason: "Instagram only connects creator and business accounts. Fill it in here instead."
    )
    static let phone = ContactPlatform(
        id: .phone, title: "Phone", call: "Add",
        method: .typed(.typePhone), handlePrefix: ""
    )

    /// The rows that authorize, and the rows that do not. The split is the
    /// question's two groups, and it is a fact about the platforms rather than a
    /// layout choice.
    static let connectable = [x, linkedin, instagram]
    static let typeable = [phone]
}

/// What the chosen platform still needs from the person.
///
/// One at a time: two open panels would be two questions, and this screen asks
/// one.
private enum ContactEntry: Hashable {
    case confirmLinkedIn
    case enterX
    case enterInstagram
    case typePhone

    var platform: MyCard.Platform {
        switch self {
        case .confirmLinkedIn: return .linkedin
        case .enterX: return .x
        case .enterInstagram: return .instagram
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
        case .enterX: value = ContactValue.xHandle(from: typed)
        case .enterInstagram: value = ContactValue.instagramHandle(from: typed)
        case .typePhone: value = ContactValue.phoneNumber(from: typed)
        }
        return value.map { ChosenContact(platform: platform, value: $0, verified: false) }
    }

    /// What the field starts with. Only LinkedIn has anything to guess from: a
    /// slug built out of the name already on the card, which the panel exists to
    /// have corrected. Wrong is fine; empty is worse.
    func guess(from name: String) -> String {
        switch self {
        case .confirmLinkedIn: return ContactValue.linkedInSlug(from: name)
        case .enterX, .enterInstagram, .typePhone: return ""
        }
    }

    /// Nil where the field speaks for itself, which is everywhere except
    /// LinkedIn.
    ///
    /// X and Instagram used to explain here why Haven asks for a link rather
    /// than reading the account. Nobody needed that: the field takes a handle
    /// straight, and a paragraph about someone else's API pricing turned a
    /// one-word answer into homework.
    var note: String? {
        switch self {
        case .confirmLinkedIn:
            // The one field that arrives pre-filled with a guess, so it is the
            // one that has to ask for a look. `connectFailure` already says the
            // connection did not go through; this only explains the guess.
            return "We guessed your address from your name -- check it."
        case .enterX, .enterInstagram, .typePhone:
            return nil
        }
    }

    var label: String {
        switch self {
        case .confirmLinkedIn: return "Your LinkedIn address"
        case .enterX: return "Your X handle"
        case .enterInstagram: return "Your Instagram handle"
        case .typePhone: return "Your phone number"
        }
    }

    var placeholder: String {
        switch self {
        case .confirmLinkedIn: return "linkedin.com/in/handle"
        case .enterX: return "@handle or link"
        case .enterInstagram: return "@handle or link"
        case .typePhone: return "Phone number"
        }
    }

    /// The address the card will carry, shown live under the field. Read off
    /// the platform rather than listed again here: two copies of the same four
    /// strings are two places for them to stop agreeing.
    var addressPrefix: String { platform.addressPrefix }

    var keyboard: UIKeyboardType {
        switch self {
        case .typePhone: return .phonePad
        case .confirmLinkedIn, .enterX, .enterInstagram: return .URL
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
