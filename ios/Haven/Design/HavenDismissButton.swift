import SwiftUI

/// The explicit way out of a dialog, on top of -- never instead of -- the
/// system swipe-to-dismiss gesture. Someone who does not already know that
/// gesture needs a control they can see, and every sheet in Haven is a
/// dialog in that sense: something opened over the screen underneath it,
/// meant to be finished and then left.
extension View {
    /// Adds the close control to a sheet's own root view. Applied once, at
    /// the top of whatever a `.sheet` presents -- including a
    /// `NavigationStack` that pushes further screens inside itself, where
    /// the control sits above the stack as a fixed overlay and so stays on
    /// screen through every push, not only the first.
    ///
    /// Not applied to `HavenScreen` itself: most of Haven's screens are
    /// pushed, not presented, and a person three taps into the directory has
    /// a back button already. This is for the surfaces that open over
    /// everything else, which is a different question with a different
    /// answer.
    func havenDismissable() -> some View {
        modifier(HavenDismissButtonOverlay())
    }
}

private struct HavenDismissButtonOverlay: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HavenColor.faint)
                    // The glyph is small; the target it sits in is not.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Close")
            .padding(.top, 4)
            .padding(.trailing, 8)
        }
    }
}

#Preview("Dismissable sheet content") {
    HavenScreen(question: "A dialog") {
        Text("Sheet content goes here.")
            .havenBody()
    } actions: {
        PrimaryButton(title: "Save") {}
    }
    .havenDismissable()
}

#Preview("Dismissable, accessibility XXXL") {
    HavenScreen(question: "A dialog") {
        Text("Sheet content goes here.")
            .havenBody()
    } actions: {
        PrimaryButton(title: "Save") {}
    }
    .havenDismissable()
    .environment(\.dynamicTypeSize, .accessibility3)
}
