import SwiftUI

/// The app once onboarding is over: People and Search, with the card reachable
/// from the People screen's toolbar.
///
/// Two tabs rather than one screen whose search field expands, per the build
/// plan's open question 3. The tab bar is also where Phase 2 grows.
struct HavenTabs: View {
    /// The Clerk user id. The directory keys its dismissed suggestions by it,
    /// so a second account on the same phone starts clean.
    let userId: String
    /// Opens straight onto My Card. The reveal's "Add another way to reach me"
    /// arrives here, and landing on People first would make that ghost button
    /// feel like it had not worked.
    var opensCard = false

    @State private var tab: Tab = .people
    @State private var peopleRoute: [Destination] = []

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $peopleRoute) {
                // People's search field is not a field: it hands the whole
                // interaction to the tab that owns searching, rather than
                // imitating it and then having to keep the two in step.
                DirectoryScreen(userId: userId, openSearch: { tab = .search })
                    .toolbar { directoryToolbar }
                    .navigationDestination(for: Destination.self) { destination in
                        switch destination {
                        case .card(let showingCode): MyCardScreen(showingCode: showingCode)
                        }
                    }
            }
            .tabItem { Label("People", systemImage: "person.2") }
            .tag(Tab.people)

            NavigationStack {
                SearchScreen()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(Tab.search)
        }
        // Selection is Star everywhere else in Haven, and the system default
        // accent is the one colour the palette does not contain.
        .tint(HavenColor.star)
        .onAppear {
            if opensCard { peopleRoute = [.card(showingCode: false)] }
        }
        // The Lock Screen widget's tap arrives here, and lands on the card
        // already turned to its code, because the code is the whole of what
        // that widget offers. The card hangs off the People tab's stack, so the
        // tab has to come along or the push lands on a stack nobody is looking
        // at.
        .onOpenURL { url in
            guard HavenDeepLink(url: url) == .beacon else { return }
            tab = .people
            peopleRoute = [.card(showingCode: true)]
        }
    }

    private enum Tab {
        case people
        case search
    }

    /// Where the People tab can go. A value rather than a view, so the reveal
    /// and the widget can open it without holding the view that shows it.
    private enum Destination: Hashable {
        case card(showingCode: Bool)
    }

    /// One door to the card, not two.
    ///
    /// There used to be a second button here for the beacon. The code is the
    /// back of the card now, so a separate way in would be a second route to
    /// the same object -- and the one that skipped the card would be the one
    /// people learned.
    @ToolbarContentBuilder
    private var directoryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: Destination.card(showingCode: false)) {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Your card")
        }
    }
}

#Preview("Tabs") {
    HavenTabs(userId: "preview_user")
}

#Preview("Tabs, accessibility XXXL") {
    HavenTabs(userId: "preview_user")
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Tabs, Reduce Motion") {
    HavenTabs(userId: "preview_user")
        .havenReduceMotion()
}
