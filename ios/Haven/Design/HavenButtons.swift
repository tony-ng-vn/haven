import SwiftUI

/// The one primary action on a screen. Cream on dark ink, full width, pinned
/// bottom. There is never a second one.
struct PrimaryButton: View {
    let title: String
    /// An SF Symbol drawn before the title, in the title's own colour and size.
    /// For a provider sign-in button whose brand mark has to sit inline with
    /// the title, in the title's own colour, rather than beside it. Everything
    /// else leaves it nil.
    var systemImage: String? = nil
    var isLoading = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            PrimaryLabel(title: title, systemImage: systemImage, isLoading: isLoading)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "Working" : "")
    }
}

/// What a primary action looks like, without being a Button.
///
/// Split out for `PhotosPicker`, which brings its own control and can only be
/// given a label. A second copy of these paddings is how two primary actions
/// end up subtly different heights.
struct PrimaryLabel: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack {
            // The label stays laid out while loading, so the button cannot
            // change height under a spinner.
            // Baseline-aligned, not centred: at accessibility text sizes the
            // title wraps, and a centred glyph then floats against the
            // middle of a two-line block instead of sitting with the words.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(HavenColor.creamInk)
            }
        }
        .font(HavenFont.buttonLabel)
        .foregroundStyle(HavenColor.creamInk)
        .padding(.vertical, 13)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(HavenColor.cream, in: RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1 : 0.3)
    }
}

/// The quiet way out: skip, or an alternative path. Never competes with the
/// primary.
struct GhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(HavenFont.ghostLabel)
                .foregroundStyle(HavenColor.muted)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// A press reads as the surface giving slightly, at the press token's 140ms.
/// Under Reduce Motion the scale is dropped rather than animated instantly --
/// a 0.98 snap is a flicker, and a press already has its own touch feedback.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // A ButtonStyle is not a DynamicProperty container, so the environment
        // has to be read inside a real view.
        PressScale(isPressed: configuration.isPressed) { configuration.label }
    }
}

private struct PressScale<Content: View>: View {
    @HavenReduceMotion private var reduceMotion
    let isPressed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .scaleEffect(reduceMotion || !isPressed ? 1 : 0.98)
            .havenAnimation(HavenMotion.press, value: isPressed)
            .contentShape(Rectangle())
    }
}

#Preview("Buttons") {
    ZStack {
        NightBackground()
        VStack(spacing: 12) {
            PrimaryButton(title: "Continue") {}
            PrimaryButton(title: "Continue") {}
                .disabled(true)
            PrimaryButton(title: "Continue", isLoading: true) {}
            GhostButton(title: "Skip for now") {}
        }
        .padding(24)
    }
}

#Preview("Buttons, accessibility XXL") {
    ZStack {
        NightBackground()
        VStack(spacing: 12) {
            PrimaryButton(title: "Continue with Google") {}
            GhostButton(title: "Other sign-in options") {}
        }
        .padding(24)
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}
