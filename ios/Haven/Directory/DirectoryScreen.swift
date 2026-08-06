import Combine
import SwiftUI

/// Screen 5 of `../../phase1-build-plan.md`: home, and an empty shell in Phase 1.
///
/// Everything that would fill it arrives later -- adding someone is Phase 2 and
/// scanning is Phase 4 -- so the empty state says what is true and sells
/// nothing. The one thing it does offer is the Lock Screen widget, because that
/// is the only thing here that works today.
struct DirectoryScreen: View {
    let userId: String
    /// The caller's own first name, for the title. Read from `HavenTabs`'s
    /// `MyNameModel` rather than a subscription of this screen's own -- see
    /// that type's doc comment for why the People screen does not open a
    /// second read of the same card.
    var firstName: String?
    /// Focusing a search field belongs to the Search tab, so the field here
    /// hands the whole interaction over rather than imitating it.
    let openSearch: () -> Void
    /// Pushes one person's screen, which is where their note gets written.
    let openPerson: (String) -> Void

    @StateObject private var model: DirectoryModel
    @State private var sheet: DirectorySheet?
    @State private var promoDismissed: Bool
    @State private var sharePromoDismissed: Bool
    /// Checks, on appear and every foreground, whether one contact is worth
    /// quietly suggesting. Its own instance keyed by `userId`, the same
    /// account-scoping `WidgetPromoDismissal` and `SharePromoDismissal` use.
    @StateObject private var contactSuggestion: ContactSuggestionModel
    /// The oldest capture `CaptureDrain` could not fully save, still unread
    /// -- checked on the same launch/foreground cadence the contact
    /// suggestion is, and also updated the moment `HandleDropState` changes:
    /// see `.onReceive` below. `CaptureSync.run(userId:)` is what records
    /// one, and it can run mid-session (a foreground-driven drain kicked off
    /// by AddPersonSheet or SearchScreen), which the poll alone would not
    /// see until the next foreground.
    @State private var droppedHandle: HandleDropState.Event?
    /// Sending what was just written is the app's job, not this screen's; it
    /// only asks. See `CaptureDrainRequest`.
    @Environment(\.requestCaptureDrain) private var requestCaptureDrain
    /// Coming back from another app is exactly the moment somebody might
    /// have just saved a new contact there -- the same reason `RootView`
    /// re-runs `CaptureSync` on this transition.
    @Environment(\.scenePhase) private var scenePhase

    init(
        userId: String,
        firstName: String? = nil,
        openSearch: @escaping () -> Void,
        openPerson: @escaping (String) -> Void
    ) {
        self.userId = userId
        self.firstName = firstName
        self.openSearch = openSearch
        self.openPerson = openPerson
        _model = StateObject(wrappedValue: DirectoryModel())
        _promoDismissed = State(
            initialValue: WidgetPromoDismissal.isDismissed(userId: userId)
        )
        _sharePromoDismissed = State(
            initialValue: SharePromoDismissal.isDismissed(userId: userId)
        )
        _contactSuggestion = StateObject(wrappedValue: ContactSuggestionModel(userId: userId))
    }

    /// A loaded screen that never opens a socket, for previews.
    init(
        userId: String,
        firstName: String? = nil,
        openSearch: @escaping () -> Void,
        openPerson: @escaping (String) -> Void = { _ in },
        preview: DirectoryLoad
    ) {
        self.userId = userId
        self.firstName = firstName
        self.openSearch = openSearch
        self.openPerson = openPerson
        _model = StateObject(wrappedValue: DirectoryModel(preview: preview))
        _promoDismissed = State(
            initialValue: WidgetPromoDismissal.isDismissed(userId: userId)
        )
        _sharePromoDismissed = State(
            initialValue: SharePromoDismissal.isDismissed(userId: userId)
        )
        _contactSuggestion = StateObject(
            wrappedValue: ContactSuggestionModel(
                userId: userId,
                provider: PreviewAddressBook(),
                mirror: { nil }
            )
        )
    }

    var body: some View {
        HavenScreen(
            contentAlignment: .top,
            header: { header },
            content: { content },
            actions: { actions }
        )
        .navigationTitle(title)
        // One presenter, not one per sheet. Stacking `.sheet` modifiers on a
        // single view is how one of them quietly stops opening -- `PhotoEditor`
        // records that failure from the card screen, and My Card folded its own
        // two into a single item for the same reason. This screen is about to
        // have three.
        .sheet(item: $sheet) { which in
            switch which {
            case .explainer:
                LockScreenExplainer()
            case .pinWalkthrough:
                PinWalkthrough()
            case .add:
                // Both read at presentation time rather than held: the mirror
                // is rewritten after every sync, and a sheet opened tomorrow
                // should not offer yesterday's directory.
                AddPersonSheet(
                    mirror: DirectoryMirrorStore.forApp().load(),
                    queue: .forApp(),
                    onSaved: onPersonAdded
                )
            }
        }
        .task {
            await contactSuggestion.checkForSuggestion()
            checkForDroppedHandle()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await contactSuggestion.checkForSuggestion() }
            checkForDroppedHandle()
        }
        // A drain that runs while this screen is already on screen --
        // AddPersonSheet and SearchScreen both ask for one on save -- would
        // otherwise only reach this screen on the next foreground. Filtered
        // to this account: `record`/`dismiss` post for whichever userId
        // scoped the `HandleDropState` that changed, and a drain that ran
        // for a different signed-in account on this device is not this
        // screen's news.
        .onReceive(NotificationCenter.default.publisher(for: HandleDropState.didChangeNotification)) { note in
            guard note.object as? String == userId else { return }
            checkForDroppedHandle()
        }
    }

    private func checkForDroppedHandle() {
        droppedHandle = HandleDropState(userId: userId).pending
    }

    /// Y1's conflict and the pre-existing handle-cap drop are different
    /// problems -- one is a save that landed missing one account, the other
    /// is a save that landed nowhere at all -- and get their own copy rather
    /// than one message stretched to fit both.
    private func droppedHandleTitle(_ event: HandleDropState.Event) -> String {
        switch event.reason {
        case .handleFull:
            return "Could not add the \(PersonReach.label(event.platform)) handle for \(event.personName)."
        case .conflict:
            return "Could not save \(event.personName)."
        }
    }

    private func droppedHandleDetail(_ event: HandleDropState.Event) -> String {
        switch event.reason {
        case .handleFull:
            return "Their handles are full."
        case .conflict:
            return "Their handle belongs to someone else in your Haven."
        }
    }

    /// The card's own action: go see the person the notice is about, and
    /// take it down, the same way accepting the contact suggestion dismisses
    /// it too. For a dropped handle that is the person it landed on; for a
    /// conflict it is the person who already, provably, owns the handle.
    private func openPersonForDroppedHandle() {
        guard let droppedHandle else { return }
        openPerson(droppedHandle.personId)
        dismissDroppedHandle()
    }

    /// Dismissing advances `HandleDropState`'s own queue, so this reads
    /// `pending` again immediately afterward rather than just clearing to
    /// nil -- whatever was queued behind the one just seen shows right away
    /// instead of waiting for the next poll or notification round-trip.
    private func dismissDroppedHandle() {
        let state = HandleDropState(userId: userId)
        state.dismiss()
        droppedHandle = state.pending
    }

    /// Queues the suggested contact and, once it has actually landed, asks
    /// for the same drain a manual save or a contact import already does.
    private func acceptContactSuggestion() {
        guard contactSuggestion.accept() else { return }
        onPersonAdded()
    }

    /// The capture is on disk; this is what turns it into a row.
    ///
    /// Without it a person added while online would not appear until the app
    /// next came back to the foreground, which reads as a save that did not
    /// work. Offline it changes nothing: the drain keeps what it could not
    /// send, and the next launch tries again.
    private func onPersonAdded() {
        Task { await requestCaptureDrain.run() }
    }

    /// "Tony's Haven", or "Your Haven" before the name is known. See
    /// `PeopleTitle` for the possessive rule.
    private var title: String {
        PeopleTitle.title(firstName: firstName)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            #if DEBUG
            // Which build this is, not just which version: two installs of
            // the same version number, one just rebuilt over the simulator,
            // otherwise read identically. Never compiled into a release or
            // App Store build -- see DevBuildLabel's own doc comment.
            if let caption = DevBuildLabel.caption(
                version: DevBuildInfo.version,
                builtAt: DevBuildInfo.builtAt
            ) {
                Text(caption)
                    .havenSecondary()
                    // Wraps rather than truncates: at accessibility sizes the
                    // default single-line clip cut it to "v1.0.0 - built
                    // Aug...", losing the one part of this line -- the time
                    // -- that actually distinguishes one build from another.
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif
            searchButton
        }
    }

    private var searchButton: some View {
        Button(action: openSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Search everyone")
                    .havenBody()
                    .foregroundStyle(HavenColor.muted)
                Spacer(minLength: 0)
            }
            // Muted rather than faint: this is the label of the control, not a
            // decoration on it, and `faint` fails 4.5:1 over the page's dusk
            // end. It reads at the top of this screen today; a screen that
            // grows a row above it would break that silently.
            .foregroundStyle(HavenColor.muted)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(HavenColor.fill, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(HavenColor.hairline)
            )
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Search everyone")
        .accessibilityHint("Opens the Search tab")
        .padding(.bottom, 4)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Ahead of even the contact suggestion: this is an actual save
            // that only partly (or not at all) landed, not a standing
            // feature or a "you might want this" guess.
            if let droppedHandle {
                PromoCard(
                    title: droppedHandleTitle(droppedHandle),
                    detail: droppedHandleDetail(droppedHandle),
                    action: "View",
                    open: openPersonForDroppedHandle,
                    dismiss: dismissDroppedHandle
                )
            }
            // Ahead of the evergreen promos: this one is about a specific
            // person, not a standing feature, and it goes stale -- someone
            // who has already decided is a worse thing to bury than a
            // suggestion that always applies.
            if let suggestion = contactSuggestion.suggestion {
                PromoCard(
                    title: "You added \(suggestion.name).",
                    detail: "Add them to Haven?",
                    action: "Add",
                    open: acceptContactSuggestion,
                    dismiss: { contactSuggestion.dismiss() }
                )
            }
            // The share sheet first, and only while the directory is empty.
            // It is the one suggestion that makes the rest of the app work --
            // Haven starts buried behind More, where nobody finds it -- and
            // somebody who already has people has plainly found a way to save
            // them.
            if model.isEmpty, !sharePromoDismissed {
                PromoCard(
                    title: "Put Haven at the front of the share sheet",
                    detail: "It starts at the back, behind More. Move it once and saving somebody is two taps.",
                    action: "Show me",
                    open: { sheet = .pinWalkthrough },
                    dismiss: {
                        SharePromoDismissal.dismiss(userId: userId)
                        sharePromoDismissed = true
                    }
                )
            }
            if !promoDismissed {
                WidgetPromoCard(
                    open: { sheet = .explainer },
                    dismiss: {
                        WidgetPromoDismissal.dismiss(userId: userId)
                        promoDismissed = true
                    }
                )
            }
            body(for: model.load)
        }
        .havenAnimation(HavenMotion.screen, value: promoDismissed)
        .havenAnimation(HavenMotion.screen, value: sharePromoDismissed)
    }

    @ViewBuilder
    private func body(for load: DirectoryLoad) -> some View {
        switch load {
        case .loading:
            ProgressView()
                .tint(HavenColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .unreachable:
            unreachable
        case .ready:
            if model.people.isEmpty {
                empty
            } else {
                list
            }
        }
    }

    private var empty: some View {
        // Says what to do now that there is something to do. Until scanning
        // existed this line was one sentence, because naming a way in that the
        // app did not have would have been worse than saying nothing.
        VStack(spacing: 6) {
            Text("No one saved yet.")
                .havenSecondary()
            Text("Scan the code on the back of somebody's card to connect.")
                .havenSecondary()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    private var unreachable: some View {
        VStack(spacing: 10) {
            Text("Haven could not load your people.")
                .havenBody()
            Text("This is a connection problem. Nothing you saved is lost.")
                .havenSecondary()
                .multilineTextAlignment(.center)
            GhostButton(title: "Try again") { model.retry() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    /// Every row opens the person, which is where their note is written.
    ///
    /// Lazy, and that is load bearing rather than an optimisation: the last row
    /// appearing is what asks for the next page, and in an eager stack every
    /// row appears at once, so the whole directory would arrive on first paint.
    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.people) { person in
                HavenRow(
                    title: person.name,
                    detail: person.detail,
                    action: { openPerson(person.id) },
                    leading: { EmptyView() },
                    trailing: { RowMark.chevron }
                )
                .onAppear {
                    // The last row, not a scroll offset: rows here are as tall
                    // as somebody's text size makes them, so an offset would be
                    // guessing at a height that changes per person.
                    if person.id == model.people.last?.id { model.loadMore() }
                }
            }
            if model.isLoadingMore {
                ProgressView()
                    .tint(HavenColor.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .accessibilityLabel("Loading more people")
            }
        }
    }

    private var actions: some View {
        PrimaryButton(title: "Add someone") { sheet = .add }
    }
}

/// What the directory can put on top of itself.
///
/// An enum rather than a boolean each, because the count is going up: the Lock
/// Screen explainer, the share-sheet walkthrough, and the add sheet that
/// arrives with manual add. One `.sheet(item:)` presents whichever is set.
private enum DirectorySheet: String, Identifiable {
    case explainer
    case pinWalkthrough
    case add

    var id: String { rawValue }
}

// MARK: - Previews

private let previewPeople = DirectoryPage(
    page: [
        DirectoryPerson(
            _id: "j5701",
            name: "Maya Chen",
            company: "Haven",
            role: "Founder",
            city: nil
        ),
        DirectoryPerson(
            _id: "j5702",
            name: "Ada Lovelace",
            company: nil,
            role: nil,
            city: DirectoryPerson.City(name: "London")
        ),
    ],
    isDone: true
)

private let emptyDirectory = DirectoryPage(page: [], isDone: true)

/// A first page that filled up, which is the state the count calls a floor and
/// the one the foot of the list grows from.
private let previewFirstPage = DirectoryPage(
    page: (0..<12).map { index in
        DirectoryPerson(
            _id: "j57\(index)",
            name: "Person \(index + 1)",
            company: index.isMultiple(of: 2) ? "Haven" : nil,
            role: nil,
            city: nil
        )
    },
    isDone: false
)

private func previewScreen(_ load: DirectoryLoad, firstName: String? = "Alex") -> some View {
    NavigationStack {
        DirectoryScreen(
            userId: "preview_user",
            firstName: firstName,
            openSearch: {},
            preview: load
        )
    }
}

#Preview("People, empty") {
    previewScreen(.ready(emptyDirectory))
}

// The title before a name has loaded, or without one to show.
#Preview("People, no name yet") {
    previewScreen(.ready(emptyDirectory), firstName: nil)
}

#Preview("People, with people") {
    previewScreen(.ready(previewPeople))
}

#Preview("People, more to come") {
    previewScreen(.ready(previewFirstPage))
}

#Preview("People, unreachable") {
    previewScreen(.unreachable)
}

#Preview("People, accessibility XXXL") {
    previewScreen(.ready(emptyDirectory))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("People, Reduce Motion") {
    previewScreen(.ready(previewPeople))
        .havenReduceMotion()
}
