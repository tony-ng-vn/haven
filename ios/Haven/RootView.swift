import ClerkKit
import SwiftUI

// Routes on Convex auth state.
// Unauthenticated: the welcome screen, which owns sign-in.
// Authenticated: onboarding, which decides for itself which question is next.
struct RootView: View {
    @StateObject private var auth = AuthModel()
    @StateObject private var captures = CaptureSync()
    @Environment(Clerk.self) private var clerk
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        LaunchLog.markOnce("RootView first body")
        // Split into `screen` and one modifier deliberately: with the switch
        // and the feedback condition in a single expression, the type-checker
        // gives up ("unable to type-check in reasonable time").
        return screen
            // Signing in is a completed task, so it gets the success haptic. It
            // lives here rather than on the welcome screen, because success
            // swaps that screen out and a haptic on a view being unmounted may
            // never fire. Only signedOut -> signedIn buzzes: a cold launch
            // arrives from .loading and stays silent, and signing out is not a
            // success.
            .sensoryFeedback(.success, trigger: phase, condition: Self.isSignIn)
    }

    @ViewBuilder
    private var screen: some View {
        switch auth.authState {
        case .loading:
            loading
        case .unauthenticated:
            WelcomeScreen()
        case .authenticated:
            signedIn
        }
    }

    /// The Clerk user id is the seed for the person's whole constellation, so
    /// onboarding cannot start without it. It lands a moment after the Convex
    /// client reports authenticated, and `.id` makes sure a different person
    /// never inherits the previous one's flow.
    @ViewBuilder
    private var signedIn: some View {
        if let userId = clerk.user?.id {
            OnboardingFlow(userId: userId)
                .id(userId)
                // Once signed in, and again on every return to the foreground:
                // coming back from another app is exactly the moment somebody
                // has just shared somebody to Haven. The extension writes
                // offline and never talks to Convex, so this is the only thing
                // that ever moves a capture into the directory.
                .task { await captures.run(userId: userId) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await captures.run(userId: userId) }
                }
                // A capture made inside the app has nothing to come back
                // from, so it asks for the same pass here rather than waiting
                // for a foreground that already happened.
                .environment(
                    \.requestCaptureDrain,
                    CaptureDrainRequest(run: { await captures.run(userId: userId) })
                )
        } else {
            loading
        }
    }

    /// On the night background rather than the system default, so launch does
    /// not flash white before the first screen paints.
    private var loading: some View {
        HavenLoadingScreen()
    }

    private var phase: Phase {
        switch auth.authState {
        case .loading: return .loading
        case .unauthenticated: return .signedOut
        case .authenticated: return .signedIn
        }
    }

    private static func isSignIn(from old: Phase, to new: Phase) -> Bool {
        old == .signedOut && new == .signedIn
    }

    /// The auth state reduced to something Equatable, so it can drive
    /// `sensoryFeedback` without depending on the SDK's own conformances.
    private enum Phase {
        case loading
        case signedOut
        case signedIn
    }
}

#Preview {
    RootView()
        .environment(Clerk.shared)
}
