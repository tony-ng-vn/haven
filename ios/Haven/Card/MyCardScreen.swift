import SwiftUI

/// Screen 7 of `../../phase1-build-plan.md`: the card plus every field, filled
/// or empty, each editable on its own.
///
/// A placeholder. The fields, the unlit-star nudges, the handle list with its
/// primary toggle, the photo add and the account deletion row are all still to
/// build; the photo work waits on an upload URL on `profiles`.
struct MyCardScreen: View {
    var body: some View {
        HavenScreen(
            question: "Your card",
            hint: "Not built yet."
        ) {
            EmptyView()
        } actions: {
            EmptyView()
        }
    }
}

#Preview("My card") {
    NavigationStack {
        MyCardScreen()
    }
}

#Preview("My card, accessibility XXXL") {
    NavigationStack {
        MyCardScreen()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("My card, Reduce Motion") {
    NavigationStack {
        MyCardScreen()
    }
    .havenReduceMotion()
}
