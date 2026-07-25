import AuthenticationServices
import ClerkKit
import ClerkKitUI
import SwiftUI

/// Screen 0. Sign-in and the mood screen are one screen: the wordmark and a
/// single line carry the mood, and signing in is the only thing to do.
///
/// Apple is the primary action because App Store guideline 4.8 requires it once
/// any third-party login exists. Every other provider stays behind the ghost,
/// which keeps this screen at one decision.
struct WelcomeScreen: View {
    @Environment(Clerk.self) private var clerk
    @HavenReduceMotion private var reduceMotion

    @State private var arrived = false
    @State private var isSigningIn = false
    @State private var showingOtherOptions = false
    @State private var failure: String?
    /// Counts failures rather than triggering on the message, so a second
    /// identical failure still gets its haptic.
    @State private var failureCount = 0

    var body: some View {
        HavenScreen(sky: nil, ambient: .welcome) {
            EmptyView()
        } content: {
            VStack(spacing: 11) {
                Text("Haven")
                    .havenWordmark()
                    .arriving(arrived, after: 0.25, still: reduceMotion)

                // The break is authored, not left to the layout: it lands at
                // the comma, where the sense breaks, and the two halves stay
                // balanced at every width.
                Text("A place where you are seen,\nand others are found.")
                    .havenTagline()
                    .multilineTextAlignment(.center)
                    .arriving(arrived, after: 0.7, still: reduceMotion)
            }
            // The eye puts the optical centre above the geometric one, so a
            // block centred exactly reads as sitting low.
            .padding(.bottom, 34)
            // One phrase to VoiceOver, rather than two fragments in sequence.
            .accessibilityElement(children: .combine)
        } actions: {
            VStack(spacing: 8) {
                if let failure {
                    Text(failure)
                        .havenBody()
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                // The Apple logo is not decoration: the HIG requires it on a
                // custom Sign in with Apple button, in the title's colour.
                PrimaryButton(
                    title: "Continue with Apple",
                    systemImage: "apple.logo",
                    isLoading: isSigningIn
                ) {
                    Task { await signInWithApple() }
                }
                .arriving(arrived, after: 1.15, still: reduceMotion)

                // Not "Other sign-in options": at accessibility text sizes that
                // wraps at its own hyphen, giving "Other sign- / in options".
                // This phrasing has no hyphen to break at.
                GhostButton(title: "Other ways to sign in") {
                    showingOtherOptions = true
                }
                .disabled(isSigningIn)
                .arriving(arrived, after: 1.32, still: reduceMotion)
            }
        }
        .sheet(isPresented: $showingOtherOptions) {
            AuthView()
        }
        .sensoryFeedback(.error, trigger: failureCount)
        .task { arrived = true }
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
            failureCount += 1
        }
    }
}

private extension View {
    /// One element of the arrival: fades and rises into place after `delay`.
    ///
    /// Under Reduce Motion the element is simply present. The sequence exists
    /// to make the screen feel assembled rather than dumped, and a person who
    /// has asked for less motion has asked for exactly that.
    func arriving(_ arrived: Bool, after delay: TimeInterval, still: Bool) -> some View {
        opacity(still || arrived ? 1 : 0)
            .offset(y: still || arrived ? 0 : 9)
            .animation(still ? nil : HavenMotion.easeOut(0.9).delay(delay), value: arrived)
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

#Preview("Reduce Motion") {
    WelcomeScreen()
        .environment(Clerk.shared)
        .havenReduceMotion()
}
