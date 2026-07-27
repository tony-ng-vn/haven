import SwiftUI

/// Screen 5 of `../../phase1-build-plan.md`: the home screen, an empty shell in
/// Phase 1.
///
/// A placeholder. The count, the visual search field, the dismissible Lock
/// Screen widget promo card and the disabled Add someone button are all still
/// to build; the ghost button below stands in for the promo card so the
/// explainer it opens is a route that actually runs.
struct DirectoryScreen: View {
    @State private var showsExplainer = false

    var body: some View {
        HavenScreen(
            header: { EmptyView() },
            content: {
                Text("No one saved yet.")
                    .havenSecondary()
            },
            actions: {
                GhostButton(title: "What the Lock Screen widget does") {
                    showsExplainer = true
                }
            }
        )
        .navigationTitle("People")
        .sheet(isPresented: $showsExplainer) {
            LockScreenExplainer()
        }
    }
}

#Preview("People") {
    NavigationStack {
        DirectoryScreen()
    }
}

#Preview("People, accessibility XXXL") {
    NavigationStack {
        DirectoryScreen()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("People, Reduce Motion") {
    NavigationStack {
        DirectoryScreen()
    }
    .havenReduceMotion()
}
