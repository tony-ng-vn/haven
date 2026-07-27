import SwiftUI

/// Everything between signing in and the card. It owns the model, so the sky and
/// the answers so far survive every question rather than being rebuilt per
/// screen, and it is the one place that decides which question is on screen.
struct OnboardingFlow: View {
    @StateObject private var model: OnboardingModel

    private let userId: String

    /// Whether the reveal has been seen and dismissed in this session. The
    /// reveal is a moment rather than a screen, so it is not somewhere the flow
    /// can return to.
    @State private var revealed = false
    /// Set by the reveal's ghost button, so the app opens on My Card.
    @State private var opensCard = false

    init(userId: String) {
        self.userId = userId
        _model = StateObject(wrappedValue: OnboardingModel(userId: userId))
    }

    var body: some View {
        // Split from the switch below deliberately: with both in one expression
        // the type-checker gives up ("unable to type-check in reasonable time").
        question
            .sensoryFeedback(.impact(weight: .light), trigger: model.commits)
    }

    @ViewBuilder
    private var question: some View {
        switch model.load {
        case .loading:
            HavenLoadingScreen()
        case .unreachable:
            CardUnreachableScreen { model.retry() }
        case .ready:
            answered
        }
    }

    @ViewBuilder
    private var answered: some View {
        if model.step == .name {
            NameScreen(model: model)
        } else if model.step == .location {
            LocationScreen(model: model)
        } else if model.step == .contact {
            ContactScreen(model: model)
        } else if let card = model.card, model.commits > 0, !revealed {
            // Only for someone who just answered something. A session that
            // opened with every question already answered has nothing to
            // reveal, and replaying the moment would cheapen it.
            CardRevealScreen(
                card: card,
                sky: model.sky,
                confirm: { revealed = true },
                addMore: {
                    opensCard = true
                    revealed = true
                }
            )
        } else {
            HavenTabs(userId: userId, opensCard: opensCard)
        }
    }
}

/// Onboarding cannot guess which question is unanswered, so a card it cannot
/// read is a stop rather than a step it skips past. The copy says what is wrong
/// and, just as importantly, what is not.
private struct CardUnreachableScreen: View {
    let retry: () -> Void

    var body: some View {
        HavenScreen(
            question: "Haven could not load your card.",
            hint: "This is a connection problem. Nothing you have answered is lost."
        ) {
            EmptyView()
        } actions: {
            PrimaryButton(title: "Try again", action: retry)
        }
    }
}

#Preview("Card unreachable") {
    CardUnreachableScreen(retry: {})
}
