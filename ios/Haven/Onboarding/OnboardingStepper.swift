import SwiftUI

/// Three hairlines over the question, one per onboarding step.
///
/// Deliberately the quietest progress indicator that still answers "how much
/// more of this is there": no numbers, no percentage, nothing that celebrates.
/// It responds to arriving at a question, never to typing in one.
struct OnboardingStepper: View {
    let step: OnboardingStep

    private static let barHeight: CGFloat = 2
    private static let gap: CGFloat = 4

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { each in
                Capsule()
                    .fill(each.rawValue <= step.rawValue ? HavenColor.star : HavenColor.hairline)
                    .frame(height: Self.barHeight)
            }
        }
        .havenAnimation(HavenMotion.screen, value: step)
        .accessibilityElement()
        .accessibilityLabel(
            "Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)"
        )
    }
}

#Preview("Stepper") {
    ZStack {
        NightBackground()
        VStack(spacing: 28) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                OnboardingStepper(step: step)
            }
        }
        .padding(24)
    }
}
