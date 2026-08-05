import SwiftUI

/// Screen 8 of `../../phase1-build-plan.md`: what the Lock Screen widget is
/// for, presented as a sheet from the People screen.
///
/// A picture, not a paragraph. iOS has no API to add a widget for someone, so
/// this screen cannot do the thing it is describing -- all it can do is show
/// what the result looks like and get out of the way. One line of words, one
/// picture, and the steps a tap deeper for whoever wants them.
///
/// PR 97 left the primary copy and the destination open, and the card's back
/// reshaped both: there is no beacon screen any more, so the widget's tap lands
/// on the card already turned to its code. Settled in wave G4 and left as it
/// is. "Your code, under the clock" is the whole pitch, and it is still true of
/// where the tap now lands -- the widget was never a route to a screen, it was
/// a route to the code, and the code moved without the promise changing.
struct LockScreenExplainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HavenScreen(
                header: { EmptyView() },
                content: {
                    VStack(spacing: 22) {
                        LockScreenMockup()
                        Text("Your code, under the clock. No unlocking, no hunting for the app.")
                            .havenBody()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                },
                actions: {
                    VStack(spacing: 8) {
                        NavigationLink {
                            WidgetHowTo()
                        } label: {
                            // Dressed as PrimaryButton, which is a Button and
                            // so cannot carry a push of its own -- PrimaryLabel
                            // is the same look with no Button attached.
                            PrimaryLabel(title: "Show me how")
                        }
                        .buttonStyle(PressScaleStyle())

                        GhostButton(title: "Not now") { dismiss() }
                    }
                }
            )
        }
        // On the whole stack, not the root screen: the close has to stay on
        // screen once "Show me how" pushes WidgetHowTo, because someone
        // reading the three steps is still inside this dialog, not a new one.
        .havenDismissable()
    }
}

/// A Lock Screen, drawn rather than photographed.
///
/// A screenshot of a real one would date the moment iOS restyles it, carry
/// somebody's actual wallpaper, and be a picture of a phone rather than a
/// picture of the idea. This is the idea: a clock, and Haven sitting under it.
private struct LockScreenMockup: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Monday 21 July")
                .font(.caption2)
                .foregroundStyle(HavenColor.muted)
            Text("9:41")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(HavenColor.ink)
                // The one place tabular figures matter: proportional digits
                // make a mocked-up time look hand-kerned.
                .monospacedDigit()
            HStack(spacing: 8) {
                widget(systemImage: "qrcode", isHaven: true)
                widget(systemImage: "calendar", isHaven: false)
                widget(systemImage: "sun.max", isHaven: false)
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.top, 34)
        // Fixed, and deliberately not Dynamic Type scaled: this is a picture of
        // a phone, and a picture that grows with the reader's text size stops
        // being one.
        .frame(width: 172, height: 300)
        .background(
            LinearGradient(
                colors: [HavenColor.dusk, HavenColor.night],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
        // hairlineStrong exists for exactly this: an edge that has to be seen.
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(HavenColor.hairlineStrong)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A Lock Screen with the Haven widget sitting under the clock")
    }

    /// One accessory-circular widget. The other two are there so Haven reads as
    /// one of a row rather than as the only thing a Lock Screen holds.
    private func widget(systemImage: String, isHaven: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isHaven ? HavenColor.star : HavenColor.faint)
            .frame(width: 38, height: 38)
            .background(
                Circle().fill(isHaven ? HavenColor.star.opacity(0.16) : HavenColor.fill)
            )
            .overlay(
                Circle().strokeBorder(
                    isHaven ? HavenColor.star.opacity(0.35) : HavenColor.hairline
                )
            )
    }
}

/// The three steps, one tap deeper.
///
/// Deeper because most people do not want them: the picture is the pitch, and
/// a wall of instructions in front of it would make adding a widget feel like
/// work before anyone has decided they want one.
private struct WidgetHowTo: View {
    private static let steps = [
        "Touch and hold your Lock Screen, then tap Customise.",
        "Tap the row under the clock, then find Haven in the list.",
        "Add the widget and tap Done.",
    ]

    var body: some View {
        HavenScreen(
            question: "Three steps",
            hint: "iOS will not let an app add a widget for you, so this part is yours.",
            contentAlignment: .top
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(HavenColor.star)
                            .frame(width: 20, alignment: .leading)
                        Text(step)
                            .havenBody()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("Lock Screen explainer") {
    LockScreenExplainer()
}

#Preview("Lock Screen explainer, accessibility XXXL") {
    LockScreenExplainer()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Lock Screen explainer, Reduce Motion") {
    LockScreenExplainer()
        .havenReduceMotion()
}

#Preview("Three steps") {
    NavigationStack {
        WidgetHowTo()
    }
}

#Preview("Three steps, accessibility XXXL") {
    NavigationStack {
        WidgetHowTo()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
