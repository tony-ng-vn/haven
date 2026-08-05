import SwiftUI

/// Teaching the one thing about Haven that iOS will not let it do for you.
///
/// Milestone 4 of `../../../docs/superpowers/plans/2026-07-26-capture-pipeline-plan.md`.
/// Haven lives in the share sheet, and there is no API to pin or reorder an
/// extension: a fresh install puts Haven at the end of the app row behind a
/// More button, which is exactly where nobody finds it. So it is taught once,
/// deliberately, the way `LockScreenExplainer` teaches the widget -- a picture
/// first, the steps a tap deeper, and no wall in front of anybody who does not
/// want them.
///
/// The one difference from the widget explainer: this one can hand over a real
/// share sheet. `ShareLink` opens the system sheet with Haven in it, so the
/// steps are followed on the real thing rather than read and remembered.
struct PinWalkthrough: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HavenScreen(
                header: { EmptyView() },
                content: {
                    VStack(spacing: 22) {
                        ShareSheetMockup()
                        Text("Haven lives in the share sheet. Move it to the front once and saving somebody is two taps from their profile.")
                            .havenBody()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                },
                actions: {
                    VStack(spacing: 8) {
                        NavigationLink {
                            PinHowTo()
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
        // screen once "Show me how" pushes PinHowTo, because someone reading
        // the three steps is still inside this dialog, not a new one.
        .havenDismissable()
    }
}

/// A share sheet, drawn rather than photographed.
///
/// Same reasoning as the Lock Screen mockup next door: a screenshot would date
/// the moment iOS restyles the sheet, and it would be a picture of a phone
/// rather than a picture of the idea. The idea is Haven sitting first in the
/// row instead of last behind More.
private struct ShareSheetMockup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share")
                .font(.caption2)
                .foregroundStyle(HavenColor.muted)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                app(systemImage: "sparkle", isHaven: true)
                app(systemImage: "message", isHaven: false)
                app(systemImage: "envelope", isHaven: false)
                app(systemImage: "ellipsis", isHaven: false)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                row("Copy", systemImage: "doc.on.doc")
                row("Add to Reading List", systemImage: "eyeglasses")
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(16)
        // Fixed, and deliberately not Dynamic Type scaled: this is a picture of
        // a phone, and a picture that grows with the reader's text size stops
        // being one.
        .frame(width: 260, height: 240)
        .background(
            LinearGradient(
                colors: [HavenColor.dusk, HavenColor.night],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(HavenColor.hairlineStrong)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A share sheet with Haven first in the row of apps")
    }

    /// One app in the row. The other three are there so Haven reads as one of
    /// a row rather than as the only thing a share sheet holds.
    private func app(systemImage: String, isHaven: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isHaven ? HavenColor.star : HavenColor.faint)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isHaven ? HavenColor.star.opacity(0.16) : HavenColor.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11).strokeBorder(
                        isHaven ? HavenColor.star.opacity(0.35) : HavenColor.hairline
                    )
                )
            Text(isHaven ? "Haven" : " ")
                .font(.system(size: 9))
                .foregroundStyle(isHaven ? HavenColor.ink : .clear)
        }
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(HavenColor.faint)
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(HavenColor.faint)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(HavenColor.hairline).frame(height: 1)
        }
    }
}

/// The three steps, on a real share sheet.
///
/// Deeper than the picture because most people do not want the steps, and the
/// picture is the pitch. What is different from the widget's version is the
/// button: iOS will not pin an extension for you, but it will open the sheet
/// where the pinning happens, so the steps are followed rather than memorised.
private struct PinHowTo: View {
    private static let steps = [
        "Scroll the row of apps to the end and tap More.",
        "Tap Edit, then turn Haven on and drag it to the top.",
        "Tap Done. Haven is at the front from now on.",
    ]

    /// What the practice sheet shares.
    ///
    /// Instagram's own account, chosen because it is a real profile Haven
    /// parses and obviously nobody's contact: somebody who taps Haven here
    /// gets the real save sheet and a practice person they will not mistake
    /// for a friend. Sharing nothing would have been a share sheet with no
    /// app row worth reading.
    private static let practiceProfile = URL(string: "https://instagram.com/instagram")!

    var body: some View {
        HavenScreen(
            question: "Three steps",
            hint: "iOS will not let an app move itself in the share sheet, so this part is yours.",
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

                Text("Tapping Haven in there saves Instagram's own account, so you have one person to practise on. Delete them whenever you like.")
                    .havenSecondary()
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            ShareLink(item: Self.practiceProfile) {
                PrimaryLabel(title: "Open a share sheet")
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Open a share sheet to practise on")
        }
    }
}

// MARK: - Previews

#Preview("Pin walkthrough") {
    PinWalkthrough()
}

#Preview("Pin walkthrough, accessibility XXXL") {
    PinWalkthrough()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Pin walkthrough, Reduce Motion") {
    PinWalkthrough()
        .havenReduceMotion()
}

#Preview("Three steps") {
    NavigationStack {
        PinHowTo()
    }
}

#Preview("Three steps, accessibility XXXL") {
    NavigationStack {
        PinHowTo()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
