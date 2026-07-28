import SwiftUI

/// A multi-line text area, styled to match `HavenField`.
///
/// Its own control rather than a taller `HavenField`: `TextField` and
/// `TextEditor` are different views with different placeholder, focus and
/// scrolling behaviour, and faking one with the other is how a note field ends
/// up unable to hold a second line.
struct HavenNoteField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    /// How tall the box starts. Generous on purpose: this field is the whole
    /// reason the person screen exists, and a one-line box asks for one line.
    var minHeight: CGFloat = 140

    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // TextEditor has no placeholder of its own, so this sits behind it
            // and is hidden from VoiceOver, which reads the field's own label.
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(HavenColor.muted)
                    // Matched to where TextEditor actually lays out its own
                    // text: 11 of padding plus the ~5 it insets internally.
                    // Measured on the simulator, not derived -- the internal
                    // inset is not a documented number.
                    .padding(.vertical, 13)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(HavenColor.ink)
                .tint(HavenColor.star)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .focused($focused)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(HavenColor.fill, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    focused ? HavenColor.star.opacity(0.55) : HavenColor.hairline,
                    lineWidth: 1
                )
        }
        // Same focus ring as HavenField: visible without colour vision, so the
        // border weight carries it too.
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(HavenColor.star.opacity(focused ? 0.12 : 0), lineWidth: 3)
                .padding(-2)
        }
        .havenAnimation(HavenMotion.press, value: focused)
        .accessibilityLabel(label)
    }
}

#Preview("Note field") {
    @Previewable @State var empty = ""
    @Previewable @State var written =
        "Met at the Founder Inc dinner.\nWorks on an infinite-context database."

    ZStack {
        NightBackground()
        VStack(spacing: 16) {
            HavenNoteField(
                label: "What you remember",
                placeholder: "What should you remember about them?",
                text: $empty
            )
            HavenNoteField(
                label: "What you remember",
                placeholder: "What should you remember about them?",
                text: $written
            )
        }
        .padding(24)
    }
}
