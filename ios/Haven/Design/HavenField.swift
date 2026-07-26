import SwiftUI

/// A single text field. Onboarding shows one at a time, so it carries no visible
/// title -- the question above it is the label. VoiceOver still needs one, which
/// is why `label` is required rather than optional.
struct HavenField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .continue
    /// Takes focus as soon as it appears. For a field that appeared *because*
    /// someone asked to type -- a panel opening under a row they tapped -- not
    /// focusing costs a second tap for nothing.
    var autofocus = false
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(HavenColor.ink)
            .tint(HavenColor.star)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(contentType == .name || keyboard == .phonePad)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .focused($focused)
            .padding(.vertical, 13)
            .padding(.horizontal, 15)
            .background(HavenColor.fill, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        focused ? HavenColor.star.opacity(0.55) : HavenColor.hairline,
                        lineWidth: 1
                    )
            }
            // A focus ring, not a glow: it has to be visible without colour
            // vision, so the border weight carries it too.
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(HavenColor.star.opacity(focused ? 0.12 : 0), lineWidth: 3)
                    .padding(-2)
            }
            .havenAnimation(HavenMotion.press, value: focused)
            .accessibilityLabel(label)
            .task {
                guard autofocus else { return }
                try? await Task.sleep(for: Self.focusDelay)
                focused = true
            }
    }

    /// Focus set on the pass that puts the field on screen is dropped silently,
    /// because the field is not in the responder chain yet. This is the wait for
    /// it to arrive, and it is not a duration anyone sees: nothing animates over
    /// it, so it does not belong in `HavenMotion`.
    private static let focusDelay = Duration.milliseconds(60)
}

#Preview("Field") {
    @Previewable @State var name = ""
    @Previewable @State var filled = "Tony Nguyen"

    ZStack {
        NightBackground()
        VStack(spacing: 12) {
            HavenField(
                label: "Your name",
                placeholder: "Your name",
                text: $name,
                contentType: .name,
                capitalization: .words
            )
            HavenField(
                label: "Your name",
                placeholder: "Your name",
                text: $filled,
                contentType: .name,
                capitalization: .words
            )
        }
        .padding(24)
    }
}
