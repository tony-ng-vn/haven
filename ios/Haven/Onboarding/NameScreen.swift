import SwiftUI

/// Onboarding question 1. The only required one: a card with no name has
/// nothing to show, and the beacon address is minted from it.
struct NameScreen: View {
    @ObservedObject var model: OnboardingModel

    @State private var name = ""

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HavenScreen(
            sky: model.sky,
            litMajors: model.litMajors,
            header: {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingStepper(step: .name)
                    QuestionHeader(question: "What is your name?")
                }
            },
            content: {
                HavenField(
                    label: "Your name",
                    placeholder: "Full name",
                    text: $name,
                    contentType: .name,
                    capitalization: .words,
                    onSubmit: commit
                )
            },
            actions: {
                VStack(spacing: 8) {
                    if let failure = model.failure {
                        Text(failure)
                            .havenBody()
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    PrimaryButton(title: "Continue", isLoading: model.isSaving, action: commit)
                        .disabled(trimmed.isEmpty)
                }
                .havenAnimation(HavenMotion.screen, value: model.failure)
            }
        )
    }

    private func commit() {
        Task { await model.saveName(trimmed) }
    }
}

#Preview("Name") {
    NameScreen(model: OnboardingModel(previewUserId: "user_2abcDEF123"))
}

#Preview("Name, accessibility XXXL") {
    NameScreen(model: OnboardingModel(previewUserId: "user_2abcDEF123"))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Name, Reduce Motion") {
    NameScreen(model: OnboardingModel(previewUserId: "user_2abcDEF123"))
        .havenReduceMotion()
}
