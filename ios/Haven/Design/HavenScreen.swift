import SwiftUI

/// The skeleton every Haven screen uses: header pinned top, interactive content
/// centred in whatever space is left, actions pinned bottom.
///
/// Content is centred but scrolls when it cannot fit, which is what keeps the
/// screens usable at accessibility text sizes. The actions never scroll away.
struct HavenScreen<Header: View, Content: View, Actions: View>: View {
    /// Nil renders ambient dust with no figure, which is the welcome screen.
    var sky: Sky?
    var litMajors: Set<Int>?
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    @State private var contentAreaHeight: CGFloat = 0

    var body: some View {
        ZStack {
            NightBackground()
            DustLayer()
            if let sky {
                SkyView(sky: sky, litMajors: litMajors)
            }

            VStack(spacing: 0) {
                header
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: contentAreaHeight, alignment: .center)
                        .padding(.vertical, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Measures the scroll view's own frame, not its content, so
                // short content can be centred in the space that is left.
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ContentAreaHeightKey.self, value: geo.size.height)
                    }
                }

                actions
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .onPreferenceChange(ContentAreaHeightKey.self) { height in
            contentAreaHeight = height
        }
    }
}

private struct ContentAreaHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension HavenScreen where Header == QuestionHeader {
    /// The common case: a question, optionally with a hint under it.
    init(
        question: String,
        hint: String? = nil,
        sky: Sky? = nil,
        litMajors: Set<Int>? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            sky: sky,
            litMajors: litMajors,
            header: { QuestionHeader(question: question, hint: hint) },
            content: content,
            actions: actions
        )
    }
}

/// A question with an optional hint. One per screen.
struct QuestionHeader: View {
    let question: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .havenQuestion()
            if let hint {
                Text(hint)
                    .havenHint()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The question is the screen's heading, so VoiceOver's heading rotor
        // should find it.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Previews

private let previewSky = SkyGenerator.build(seed: "user_2abcDEF123")

#Preview("Screen skeleton") {
    @Previewable @State var name = ""

    HavenScreen(
        question: "What is your name?",
        sky: previewSky,
        litMajors: StarSlot.litMajorIndices(filled: [], majorCount: previewSky.majors.count)
    ) {
        HavenField(
            label: "Your name",
            placeholder: "Your name",
            text: $name,
            contentType: .name,
            capitalization: .words
        )
    } actions: {
        PrimaryButton(title: "Continue") {}
            .disabled(name.isEmpty)
    }
}

#Preview("Screen skeleton with a hint and suggestion rows") {
    @Previewable @State var city = "Ho Chi"

    HavenScreen(
        sky: previewSky,
        litMajors: StarSlot.litMajorIndices(filled: [.name], majorCount: previewSky.majors.count),
        header: {
            QuestionHeader(
                question: "Where are you based?",
                hint: "City only. Never your street address."
            )
        },
        content: {
            VStack(alignment: .leading, spacing: 0) {
                HavenField(
                    label: "Your city",
                    placeholder: "Start typing a city",
                    text: $city,
                    capitalization: .words
                )
                .padding(.bottom, 8)
                HavenRow(title: "Ho Chi Minh City", detail: "Vietnam", action: {})
                HavenRow(title: "Ho Chi Minh City Province", detail: "Vietnam", action: {})
            }
        },
        actions: {
            VStack(spacing: 8) {
                PrimaryButton(title: "Continue") {}
                GhostButton(title: "Skip for now") {}
            }
        }
    )
}

// Long content at an accessibility size has to scroll rather than crush the
// actions off the bottom of the screen.
#Preview("Screen skeleton, accessibility XXXL") {
    @Previewable @State var name = ""

    HavenScreen(
        question: "How should people reach you?",
        hint: "Connect an account and we fill in the rest. We never post.",
        sky: previewSky
    ) {
        VStack(alignment: .leading, spacing: 0) {
            HavenRow(title: "Instagram", action: {}) { RowAccessory(text: "Connect") }
            HavenRow(title: "X", action: {}) { RowAccessory(text: "Connect") }
            HavenRow(title: "LinkedIn", action: {}) { RowAccessory(text: "Connect") }
            HavenRow(title: "Phone", action: {}) { RowAccessory(text: "Add") }
        }
    } actions: {
        VStack(spacing: 8) {
            PrimaryButton(title: "Continue") {}
                .disabled(name.isEmpty)
            GhostButton(title: "Skip for now") {}
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
