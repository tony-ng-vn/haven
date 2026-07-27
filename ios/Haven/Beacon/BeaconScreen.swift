import SwiftUI

/// Screen 9 of `../../phase1-build-plan.md`: the QR someone else points a
/// camera at.
///
/// A placeholder, and unreachable while `FeatureFlags.beaconEnabled` is false.
/// The real QR, the address in mono, and the brightness boost are all still to
/// build.
struct BeaconScreen: View {
    var body: some View {
        HavenScreen(
            question: "Your beacon",
            hint: "Not built yet."
        ) {
            EmptyView()
        } actions: {
            EmptyView()
        }
    }
}

#Preview("Beacon") {
    NavigationStack {
        BeaconScreen()
    }
}

#Preview("Beacon, accessibility XXXL") {
    NavigationStack {
        BeaconScreen()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Beacon, Reduce Motion") {
    NavigationStack {
        BeaconScreen()
    }
    .havenReduceMotion()
}
