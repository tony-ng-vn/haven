import ClerkKit
import ClerkKitUI
import SwiftUI

/// Screen 0. Sign-in and the mood screen are one screen: the wordmark and a
/// single line carry the mood, and the two doors into an account are the
/// only decisions here.
///
/// Sign up and sign in are two different flows, chosen up front, rather than
/// one "Continue" that guesses which a person meant and asks again if it
/// guessed wrong.
struct WelcomeScreen: View {
    @HavenReduceMotion private var reduceMotion

    @State private var arrived = false
    @State private var authSheet: AuthSheet?
    @State private var legalDocument: LegalDocument?

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
                // Sign up leads: a pre-launch app has no existing users, so
                // nearly everyone who reaches this screen needs an account
                // rather than a way back into one they already have.
                //
                // Apple is not one of the two doors here. Removed 2026-08-04:
                // the production Clerk plan allows at most three social
                // connections, and Google, LinkedIn and X spend all three.
                // Guideline 4.8 requires a privacy-equivalent login (Sign in
                // with Apple) once a third-party login exists, so this has to
                // come back before App Store submission -- it is set aside
                // for now, not a decision to ship without it.
                PrimaryButton(title: "Sign up") {
                    authSheet = .signUp
                }
                .arriving(arrived, after: 1.15, still: reduceMotion)

                GhostButton(title: "Sign in") {
                    authSheet = .signIn
                }
                .arriving(arrived, after: 1.32, still: reduceMotion)

                // Guideline 5.1.1(i) wants the privacy policy reachable inside
                // the app, and this screen is where someone decides whether to
                // sign in at all, so the pages are offered before the account
                // exists, not only after (My Card carries them too).
                legalLinks
                    .arriving(arrived, after: 1.45, still: reduceMotion)
            }
        }
        .sheet(item: $authSheet) { sheet in
            AuthView(mode: sheet.mode)
        }
        .legalSheet($legalDocument)
        .task { arrived = true }
    }

    /// Side by side while they fit, stacked at accessibility sizes, where two
    /// titles this long cannot share a line without truncating.
    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) { legalButtons }
            VStack(spacing: 10) { legalButtons }
        }
        .padding(.top, 4)
    }

    private var legalButtons: some View {
        ForEach(LegalDocument.allCases) { document in
            Button {
                legalDocument = document
            } label: {
                Text(document.title)
                    .havenSecondary()
            }
        }
    }

    /// Which mode `AuthView` opens in. One sheet rather than two `.sheet`
    /// modifiers on this view, which already carries the legal sheet as
    /// well -- a screen stacking three presentations is a screen where one
    /// of them quietly stops opening.
    private enum AuthSheet: Identifiable {
        case signUp
        case signIn

        var id: Self { self }

        var mode: AuthView.Mode {
            switch self {
            case .signUp: return .signUp
            case .signIn: return .signIn
            }
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

#Preview {
    WelcomeScreen()
        .environment(Clerk.shared)
}

#Preview("Welcome, accessibility XXXL") {
    WelcomeScreen()
        .environment(Clerk.shared)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Reduce Motion") {
    WelcomeScreen()
        .environment(Clerk.shared)
        .havenReduceMotion()
}
