import ClerkKit
import SwiftUI

// Routes on Convex auth state.
// Unauthenticated: the welcome screen, which owns sign-in.
// Authenticated: onboarding, which decides for itself which question is next.
struct RootView: View {
    @StateObject private var auth = AuthModel()
    @Environment(Clerk.self) private var clerk

    var body: some View {
        // Split into `screen` and one modifier deliberately: with the switch
        // and the feedback condition in a single expression, the type-checker
        // gives up ("unable to type-check in reasonable time").
        screen
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
            OnboardingFlow(userId: userId).id(userId)
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
