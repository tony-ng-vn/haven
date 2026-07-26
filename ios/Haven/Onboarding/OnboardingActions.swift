import SwiftUI

/// The bottom of every onboarding question: what went wrong, the way forward,
/// and the way past.
///
/// One control rather than three copies, so a change to how a question ends
/// happens once. The name question passes no skip, which is the only difference
/// between them and is exactly the difference that matters.
struct OnboardingActions: View {
    var failure: String?
    var isSaving = false
    let canContinue: Bool
    let onContinue: () -> Void
    /// Nil on the one question that has to be answered.
    var onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            if let failure {
                Text(failure)
                    .havenBody()
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            PrimaryButton(title: "Continue", isLoading: isSaving, action: onContinue)
                .disabled(!canContinue)
            if let onSkip {
                GhostButton(title: "Skip for now", action: onSkip)
                    .disabled(isSaving)
            }
        }
        .havenAnimation(HavenMotion.screen, value: failure)
    }
}

#Preview("Actions") {
    ZStack {
        NightBackground()
        VStack(spacing: 40) {
            OnboardingActions(canContinue: false, onContinue: {})
            OnboardingActions(canContinue: true, onContinue: {}, onSkip: {})
            OnboardingActions(
                failure: "That did not save. Check your connection and try again.",
                canContinue: true,
                onContinue: {},
                onSkip: {}
            )
        }
        .padding(24)
    }
}
