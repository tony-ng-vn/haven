import SwiftUI

/// Screen 5 of `../../phase1-build-plan.md`: home, and an empty shell in Phase 1.
///
/// Everything that would fill it arrives later -- adding someone is Phase 2 and
/// scanning is Phase 4 -- so the empty state says what is true and sells
/// nothing. The one thing it does offer is the Lock Screen widget, because that
/// is the only thing here that works today.
struct DirectoryScreen: View {
    let userId: String
    /// Focusing a search field belongs to the Search tab, so the field here
    /// hands the whole interaction over rather than imitating it.
    let openSearch: () -> Void
    /// Pushes one person's screen, which is where their note gets written.
    let openPerson: (String) -> Void

    @StateObject private var model: DirectoryModel
    @State private var showsExplainer = false
    @State private var showsAdd = false
    @State private var promoDismissed: Bool
    /// Sending what was just written is the app's job, not this screen's; it
    /// only asks. See `CaptureDrainRequest`.
    @Environment(\.requestCaptureDrain) private var requestCaptureDrain

    init(
        userId: String,
        openSearch: @escaping () -> Void,
        openPerson: @escaping (String) -> Void
    ) {
        self.userId = userId
        self.openSearch = openSearch
        self.openPerson = openPerson
        _model = StateObject(wrappedValue: DirectoryModel())
        _promoDismissed = State(
            initialValue: WidgetPromoDismissal.isDismissed(userId: userId)
        )
    }

    /// A loaded screen that never opens a socket, for previews.
    init(
        userId: String,
        openSearch: @escaping () -> Void,
        openPerson: @escaping (String) -> Void = { _ in },
        preview: DirectoryLoad
    ) {
        self.userId = userId
        self.openSearch = openSearch
        self.openPerson = openPerson
        _model = StateObject(wrappedValue: DirectoryModel(preview: preview))
        _promoDismissed = State(
            initialValue: WidgetPromoDismissal.isDismissed(userId: userId)
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
        .sheet(isPresented: $showsExplainer) {
            LockScreenExplainer()
        }
        // Both read at presentation time rather than held: the mirror is
        // rewritten after every sync, and a sheet opened tomorrow should not
        // offer yesterday's directory.
        .sheet(isPresented: $showsAdd) {
            AddPersonSheet(
                mirror: DirectoryMirrorStore.forApp().load(),
                queue: .forApp(),
                onSaved: onPersonAdded
            )
        }
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

    /// "People", with a count once there is one worth giving.
    ///
    /// Nobody is left off rather than shown as a zero: the empty state below
    /// already says it, and a title reading "People 0" says it twice and colder.
    private var title: String {
        guard let count = model.count, count > 0 else { return "People" }
        // A first page that filled up has more behind it, so the number is a
        // floor rather than a total, and says so.
        return model.countIsPartial ? "People \(count)+" : "People \(count)"
    }

    private var header: some View {
        Button(action: openSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Search everyone")
                    .havenBody()
                    .foregroundStyle(HavenColor.faint)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HavenColor.faint)
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
            if !promoDismissed {
                WidgetPromoCard(
                    open: { showsExplainer = true },
                    dismiss: {
                        WidgetPromoDismissal.dismiss(userId: userId)
                        promoDismissed = true
                    }
                )
            }
            body(for: model.load)
        }
        .havenAnimation(HavenMotion.screen, value: promoDismissed)
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
        Text("No one saved yet.")
            .havenSecondary()
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
    private var list: some View {
        VStack(spacing: 0) {
            ForEach(model.people) { person in
                HavenRow(
                    title: person.name,
                    detail: person.detail,
                    action: { openPerson(person.id) },
                    leading: { EmptyView() },
                    trailing: { RowMark.chevron }
                )
            }
        }
    }

    private var actions: some View {
        PrimaryButton(title: "Add someone") { showsAdd = true }
    }
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

private func previewScreen(_ load: DirectoryLoad) -> some View {
    NavigationStack {
        DirectoryScreen(userId: "preview_user", openSearch: {}, preview: load)
    }
}

#Preview("People, empty") {
    previewScreen(.ready(emptyDirectory))
}

#Preview("People, with people") {
    previewScreen(.ready(previewPeople))
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
