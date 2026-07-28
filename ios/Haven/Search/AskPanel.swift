import SwiftUI

/// The answer to a question about your network, under the search field.
///
/// Not a chat surface: `people:ask` answers or asks exactly one question per
/// call, and it always comes back with people rather than prose. A thread of
/// bubbles would promise an open-ended conversation this is not.
struct AskPanel: View {
    @ObservedObject var model: AskModel
    /// Opens one person. An answer that named somebody and then made you go
    /// and find them was the ask stopping one step short.
    var openPerson: (String) -> Void = { _ in }
    /// Clears the answer and hands the screen back to search.
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.state {
            case .idle:
                EmptyView()
            case .thinking:
                thinking
            case .failed(let message):
                failed(message)
            case .answered(let answer):
                answered(answer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thinking: some View {
        HStack(spacing: 10) {
            ProgressView().tint(HavenColor.faint)
            Text("Reading everyone you know...")
                .havenSecondary()
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .havenSecondary()
            GhostButton(title: "Back to search", action: onDismiss)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func answered(_ answer: AskAnswer) -> some View {
        if let question = answer.clarifyingQuestion {
            clarifying(question)
        } else if answer.matches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Named for what it is. An ask that pads an empty answer with
                // the nearest person is worse than one that says nobody.
                Text("Nobody you know fits that.")
                    .havenSecondary()
                GhostButton(title: "Back to search", action: onDismiss)
            }
            .padding(.top, 8)
        } else {
            matches(answer.matches)
        }
    }

    /// One question rather than a guess, with somewhere to answer it.
    private func clarifying(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .havenBody()
                .accessibilityAddTraits(.isHeader)
            HavenField(
                label: question,
                placeholder: "Tell Haven more",
                text: $model.reply,
                submitLabel: .send,
                autofocus: true,
                onSubmit: { Task { await model.sendReply() } }
            )
            HStack(spacing: 10) {
                PrimaryButton(title: "Answer") {
                    Task { await model.sendReply() }
                }
                .disabled(!model.canSendReply)
                GhostButton(title: "Never mind", action: onDismiss)
            }
        }
        .padding(.top, 4)
    }

    private func matches(_ matches: [AskMatch]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matches) { match in
                AskMatchRow(match: match, open: { openPerson(match.personId) })
            }
            GhostButton(title: "Back to search", action: onDismiss)
                .padding(.top, 14)
        }
    }
}

/// One person the answer named, with the reason underneath.
///
/// The reason is the point. A result with no "because you wrote ..." reads as
/// random, and this screen is spending a model call precisely to have one.
struct AskMatchRow: View {
    let match: AskMatch
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(match.name)
                        .personName(.row)
                        .foregroundStyle(HavenColor.ink)
                    if match.kind == .bridge {
                        bridgeTag
                    }
                }
                // The reason reads brighter than the placing line, not dimmer:
                // spending a model call buys the "because you wrote ..." and
                // that is what someone is here to read.
                if let detail = match.detail {
                    Text(detail)
                        .havenSecondary()
                        .foregroundStyle(HavenColor.faint)
                }
                Text(match.why)
                    .havenSecondary()
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(HavenColor.hairline)
                    .frame(height: 1)
            }
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
    }

    /// A bridge is a different kind of answer, not a weaker one, so it is
    /// labelled rather than dimmed.
    private var bridgeTag: some View {
        Text("BRIDGE")
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(HavenColor.star)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(HavenColor.star.opacity(0.14), in: Capsule())
    }

    /// VoiceOver gets the kind as a word: the tag is visual, and "bridge" is
    /// the difference between "they can help" and "they know someone who can".
    private var spoken: String {
        let kind = match.kind == .bridge ? "Bridge" : "Direct match"
        return [match.name, kind, match.detail, match.why]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

// MARK: - Previews

private let previewMatches = [
    AskMatch(
        personId: "1",
        name: "Ada Lovelace",
        company: "Analytical Engines",
        role: "Engineer",
        cityName: nil,
        kind: .direct,
        why: "You wrote that she works on an infinite-context-window database."
    ),
    AskMatch(
        personId: "2",
        name: "Alan Turing",
        company: "Y Combinator",
        role: "Analyst",
        cityName: "San Francisco",
        kind: .bridge,
        why: "He screens winter batch applications, so he almost certainly knows founders."
    ),
]

#Preview("Answered") {
    ZStack {
        NightBackground()
        ScrollView {
            AskPanel(
                model: AskModel(preview: .answered(AskAnswer(matches: previewMatches))),
                onDismiss: {}
            )
            .padding(24)
        }
    }
}

#Preview("Asks a question back") {
    ZStack {
        NightBackground()
        AskPanel(
            model: AskModel(
                preview: .answered(
                    AskAnswer(clarifyingQuestion: "What do you need them for?")
                )
            ),
            onDismiss: {}
        )
        .padding(24)
    }
}

#Preview("Nobody fits") {
    ZStack {
        NightBackground()
        AskPanel(model: AskModel(preview: .answered(AskAnswer())), onDismiss: {})
            .padding(24)
    }
}

#Preview("Thinking") {
    ZStack {
        NightBackground()
        AskPanel(model: AskModel(preview: .thinking), onDismiss: {})
            .padding(24)
    }
}
