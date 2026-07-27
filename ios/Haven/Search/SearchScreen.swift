import SwiftUI

/// Screen 6 of `../../phase1-build-plan.md`: search, a shell in Phase 1.
///
/// A placeholder. The field, the company, city and role chips, and the results
/// list with its reserved interp-line slot are all still to build. Wiring
/// arrives in Phase 3.
struct SearchScreen: View {
    var body: some View {
        HavenScreen(
            header: { EmptyView() },
            content: {
                Text("Search is not wired up yet.")
                    .havenSecondary()
            },
            actions: { EmptyView() }
        )
        .navigationTitle("Search")
    }
}

#Preview("Search") {
    NavigationStack {
        SearchScreen()
    }
}

#Preview("Search, accessibility XXXL") {
    NavigationStack {
        SearchScreen()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Search, Reduce Motion") {
    NavigationStack {
        SearchScreen()
    }
    .havenReduceMotion()
}
