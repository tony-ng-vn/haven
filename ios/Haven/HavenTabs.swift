import SwiftUI

/// The app once onboarding is over: People and Search, with the card and the
/// beacon reachable from the People screen's toolbar.
///
/// Two tabs rather than one screen whose search field expands, per the build
/// plan's open question 3. The tab bar is also where Phase 2 grows.
struct HavenTabs: View {
    var body: some View {
        TabView {
            NavigationStack {
                DirectoryScreen()
                    .toolbar { directoryToolbar }
            }
            .tabItem { Label("People", systemImage: "person.2") }

            NavigationStack {
                SearchScreen()
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        // Selection is Star everywhere else in Haven, and the system default
        // accent is the one colour the palette does not contain.
        .tint(HavenColor.star)
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
    HavenTabs()
}

#Preview("Tabs, accessibility XXXL") {
    HavenTabs()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Tabs, Reduce Motion") {
    HavenTabs()
        .havenReduceMotion()
}
