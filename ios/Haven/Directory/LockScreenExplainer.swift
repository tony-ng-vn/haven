import SwiftUI

/// Screen 8 of `../../phase1-build-plan.md`: what the Lock Screen widget is
/// for, presented as a sheet from the People screen.
///
/// A placeholder. The Lock Screen mockup drawn in SwiftUI, the one line of
/// copy, "See what it opens", "Not now", and the three-step how-to one tap
/// deeper are all still to build.
struct LockScreenExplainer: View {
    var body: some View {
        HavenScreen(
            question: "The Lock Screen widget",
            hint: "Not built yet."
        ) {
            EmptyView()
        } actions: {
            EmptyView()
        }
    }
}

#Preview("Lock Screen explainer") {
    LockScreenExplainer()
}

#Preview("Lock Screen explainer, accessibility XXXL") {
    LockScreenExplainer()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Lock Screen explainer, Reduce Motion") {
    LockScreenExplainer()
        .havenReduceMotion()
}
