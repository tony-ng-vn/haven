import ClerkKit
import SwiftUI

// Routes on Convex auth state.
// Unauthenticated: the welcome screen, which owns sign-in.
// Authenticated: the Phase 0 probe, until onboarding replaces it.
struct RootView: View {
    @StateObject private var auth = AuthModel()

    var body: some View {
        switch auth.authState {
        case .loading:
            // On the night background rather than the system default, so
            // launch does not flash white before the first screen paints.
            ZStack {
                NightBackground()
                ProgressView()
                    .tint(HavenColor.ink)
            }
            .ignoresSafeArea()
        case .unauthenticated:
            WelcomeScreen()
        case .authenticated:
            ProfileProbeView()
        }
    }
}

#Preview {
    RootView()
        .environment(Clerk.shared)
}
