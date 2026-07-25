import SwiftUI

/// The one primary action on a screen. Cream on dark ink, full width, pinned
/// bottom. There is never a second one.
struct PrimaryButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ZStack {
                // The label stays laid out while loading, so the button cannot
                // change height under a spinner.
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(HavenColor.creamInk)
                }
            }
            .font(HavenFont.buttonLabel)
            .foregroundStyle(HavenColor.creamInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 20)
            .background(HavenColor.cream, in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? "Working" : "")
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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
            PrimaryButton(title: "Continue with Apple") {}
            GhostButton(title: "Other sign-in options") {}
        }
        .padding(24)
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}
