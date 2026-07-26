import SwiftUI

/// Onboarding question 2. Skippable: a card without a city still works, it just
/// leaves that star unlit for the edit screen to point at later.
struct LocationScreen: View {
    @ObservedObject var model: OnboardingModel
    @StateObject private var completer = CityCompleter()

    @State private var query = ""
    /// Set once a tapped suggestion resolves to a real city. Cleared the moment
    /// the person types again, so Continue can never send a structured city that
    /// no longer matches what is in the field.
    @State private var chosen: CityInput?

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Writes through the setter rather than using `onChange`, because `choose`
    /// also writes `query`: on a shared path, picking a suggestion would clear
    /// the city it had just chosen.
    private var typing: Binding<String> {
        Binding(
            get: { query },
            set: { typed in
                query = typed
                chosen = nil
                completer.search(typed)
            }
        )
    }

    var body: some View {
        HavenScreen(
            sky: model.sky,
            litMajors: model.litMajors,
            // The suggestion list grows as you type. Centred, that would push
            // the field up out from under your finger on every keystroke.
            contentAlignment: .top,
            header: {
                VStack(alignment: .leading, spacing: 18) {
                    OnboardingStepper(step: .location)
                    QuestionHeader(
                        question: "Where are you based?",
                        hint: "City only. Never your street address."
                    )
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    HavenField(
                        label: "Your city",
                        placeholder: "Start typing a city",
                        text: typing,
                        capitalization: .words,
                        autofocus: true,
                        onSubmit: commit
                    )
                    .padding(.bottom, 8)
                    ForEach(completer.suggestions) { suggestion in
                        HavenRow(
                            title: suggestion.title,
                            detail: suggestion.subtitle,
                            action: { choose(suggestion) }
                        )
                    }
                }
            },
            actions: {
                OnboardingActions(
                    failure: model.failure,
                    isSaving: model.isSaving,
                    canContinue: !trimmed.isEmpty,
                    onContinue: commit,
                    onSkip: { model.skip(.location) }
                )
            }
        )
    }

    private func choose(_ suggestion: CitySuggestion) {
        query = suggestion.title
        completer.clear()
        Task {
            let city = await completer.resolve(suggestion) ?? CityInput(name: suggestion.title)
            // The lookup is a round trip, and the person may have started typing
            // again while it ran. Applying it then would overwrite their
            // keystrokes with a city they had already moved on from.
            guard query == suggestion.title else { return }
            chosen = city
            // The field shows the city that will be stored, not the row that was
            // tapped. MapKit labels a row "San Francisco, CA" and answers "SF"
            // with the same place, and the card carries neither of those --
            // it carries the locality, which is what makes two spellings of one
            // city the same city.
            query = city.name
        }
    }

    /// Sends the resolved city when there is one, and the typed text when there
    /// is not. The typed fallback is the point: MapKit does not know every place
    /// someone lives, and being unknown to MapKit is not a reason to be told to
    /// skip the question.
    private func commit() {
        Task { await model.saveCity(chosen ?? CityInput(name: trimmed)) }
    }
}

#Preview("Location") {
    LocationScreen(
        model: OnboardingModel(
            previewUserId: "user_2abcDEF123",
            card: MyCard(username: "tony", name: "Tony Nguyen")
        )
    )
}

#Preview("Location, accessibility XXXL") {
    LocationScreen(
        model: OnboardingModel(
            previewUserId: "user_2abcDEF123",
            card: MyCard(username: "tony", name: "Tony Nguyen")
        )
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Location, Reduce Motion") {
    LocationScreen(
        model: OnboardingModel(
            previewUserId: "user_2abcDEF123",
            card: MyCard(username: "tony", name: "Tony Nguyen")
        )
    )
    .havenReduceMotion()
}
