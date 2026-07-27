import SwiftUI

/// The app once onboarding is over: People and Search, with the card and the
/// beacon reachable from the People screen's toolbar.
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
                        case .card: MyCardScreen()
                        case .beacon: BeaconScreen()
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
            if opensCard { peopleRoute = [.card] }
        }
        // The Lock Screen widget's tap arrives here. The beacon hangs off the
        // People tab's stack, so the tab has to come along or the push lands
        // on a stack nobody is looking at.
        //
        // Behind the same flag as the toolbar button: the widget is one more
        // way into the beacon, and a second door governed by a second switch
        // is how a flagged-off screen ends up reachable anyway.
        .onOpenURL { url in
            guard Self.opensBeacon(url) else { return }
            tab = .people
            peopleRoute = [.beacon]
        }
    }

    /// Whether a url should open the beacon.
    ///
    /// Separated from the view so the flag half can be tested. That half is the
    /// safety-critical one: the widget is a door into the beacon that the
    /// toolbar's own check does not cover, and a door governed by no switch is
    /// how a flagged-off screen becomes reachable anyway.
    static func opensBeacon(_ url: URL) -> Bool {
        FeatureFlags.beaconEnabled && HavenDeepLink(url: url) == .beacon
    }

    private enum Tab {
        case people
        case search
    }

    /// Where the People tab can go. A value rather than a view, so the reveal
    /// can open one of them without holding the view that shows it.
    private enum Destination: Hashable {
        case card
        case beacon
    }

    @ToolbarContentBuilder
    private var directoryToolbar: some ToolbarContent {
        if FeatureFlags.beaconEnabled {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Destination.beacon) {
                    Image(systemName: "qrcode")
                }
                .accessibilityLabel("Your beacon")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: Destination.card) {
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
