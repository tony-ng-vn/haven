import AuthenticationServices
import ClerkKit
import ClerkKitUI
import SwiftUI

/// Screen 0. Sign-in and the mood screen are one screen: the wordmark and a
/// single tagline carry the mood, and signing in is the only thing to do.
///
/// Apple is the primary action because App Store guideline 4.8 requires it
/// once any third-party login exists. Every other provider stays behind the
/// ghost, which keeps this screen at one decision.
///
/// The sky is ambient dust with no figure: the constellation is minted from
/// the Convex user id, and before sign-in there is no user to mint from.
struct WelcomeScreen: View {
    @Environment(Clerk.self) private var clerk

    @State private var isSigningIn = false
    @State private var showingOtherOptions = false
    @State private var failure: String?

    var body: some View {
        HavenScreen(sky: nil) {
            EmptyView()
        } content: {
            VStack(spacing: 12) {
                Text("Haven")
                    .havenWordmark()
                Text("Everyone you meet, findable later.")
                    .havenSecondary()
                    .multilineTextAlignment(.center)
            }
            // One phrase to VoiceOver, rather than two fragments in sequence.
            .accessibilityElement(children: .combine)
        } actions: {
            VStack(spacing: 8) {
                if let failure {
                    Text(failure)
                        .havenBody()
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .accessibilityAddTraits(.isStaticText)
                }

                PrimaryButton(title: "Continue with Apple", isLoading: isSigningIn) {
                    Task { await signInWithApple() }
                }

                GhostButton(title: "Other sign-in options") {
                    showingOtherOptions = true
                }
                .disabled(isSigningIn)
            }
        }
        .sheet(isPresented: $showingOtherOptions) {
            AuthView()
        }
    }

    private func signInWithApple() async {
        failure = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await clerk.auth.signInWithApple()
        } catch {
            // Dismissing the system sheet is a choice, not a failure, so it
            // must not leave an error sitting on the screen.
            guard !error.isAppleSignInCancellation else { return }
            failure = "That did not go through. Try again, or use another option."
        }
    }
}

private extension Error {
    var isAppleSignInCancellation: Bool {
        (self as? ASAuthorizationError)?.code == .canceled
    }
}

#Preview {
    WelcomeScreen()
        .environment(Clerk.shared)
}
