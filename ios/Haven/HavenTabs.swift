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

    @State private var tab: Tab = .people

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                // People's search field is not a field: it hands the whole
                // interaction to the tab that owns searching, rather than
                // imitating it and then having to keep the two in step.
                DirectoryScreen(userId: userId, openSearch: { tab = .search })
                    .toolbar { directoryToolbar }
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
    }

    private enum Tab {
        case people
        case search
    }

    @ToolbarContentBuilder
    private var directoryToolbar: some ToolbarContent {
        if FeatureFlags.beaconEnabled {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    BeaconScreen()
                } label: {
                    Image(systemName: "qrcode")
                }
                .accessibilityLabel("Your beacon")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                MyCardScreen()
            } label: {
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
