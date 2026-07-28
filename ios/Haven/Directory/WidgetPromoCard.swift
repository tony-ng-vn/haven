import SwiftUI

/// The one suggestion the directory makes: put Haven on the Lock Screen.
///
/// A card rather than a step in onboarding, and dismissible, because iOS has no
/// API to add a widget for someone. All this can do is ask, so it asks once and
/// takes no for an answer.
struct WidgetPromoCard: View {
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        PromoCard(
            title: "Your code, one tap from the Lock Screen",
            detail: "Add the widget and your code is there when you need it.",
            action: "See how",
            open: open,
            dismiss: dismiss
        )
    }
}

/// The shape both of the directory's suggestions take.
///
/// Two of them now -- the Lock Screen widget and Haven's place in the share
/// sheet -- and they are the same card for the same reason: each asks for
/// something iOS will not let an app do for somebody, so each can only ask,
/// once, and take no for an answer. One shape rather than two that drift.
struct PromoCard: View {
    let title: String
    let detail: String
    let action: String
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .havenBody()
                // Room for the dismiss target, which floats over the card
                // rather than sitting in this stack: at 44pt it would set the
                // height of the whole first line.
                .padding(.trailing, 28)
            Text(detail)
                .havenSecondary()
            Button(action: open) {
                Text(action)
                    .font(HavenFont.buttonLabel)
                    .foregroundStyle(HavenColor.star)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(PressScaleStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(HavenColor.fill, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(HavenColor.hairline)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HavenColor.faint)
                    // The glyph is small; the target it sits in is not.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Dismiss")
        }
    }
}

/// Whether this person has dismissed the share-sheet card.
///
/// Its own key rather than a shared one: turning down the widget says nothing
/// about wanting Haven in the share sheet, and one dismissal hiding both
/// suggestions would take away the one that matters most.
enum SharePromoDismissal {
    static func isDismissed(userId: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(userId))
    }

    static func dismiss(userId: String) {
        UserDefaults.standard.set(true, forKey: key(userId))
    }

    static func reset(userId: String) {
        UserDefaults.standard.removeObject(forKey: key(userId))
    }

    private static func key(_ userId: String) -> String {
        "haven.directory.sharePromoDismissed.\(userId)"
    }
}

#Preview("Share sheet promo card") {
    ZStack {
        NightBackground()
        PromoCard(
            title: "Put Haven at the front of the share sheet",
            detail: "It starts at the back, behind More. Move it once and saving somebody is two taps.",
            action: "Show me",
            open: {},
            dismiss: {}
        )
        .padding(24)
    }
    .ignoresSafeArea()
}

#Preview("Widget promo card") {
    ZStack {
        NightBackground()
        WidgetPromoCard(open: {}, dismiss: {})
            .padding(24)
    }
    .ignoresSafeArea()
}

#Preview("Widget promo card, accessibility XXXL") {
    ZStack {
        NightBackground()
        ScrollView {
            WidgetPromoCard(open: {}, dismiss: {})
                .padding(24)
        }
    }
    .ignoresSafeArea()
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Widget promo card, Reduce Motion") {
    ZStack {
        NightBackground()
        WidgetPromoCard(open: {}, dismiss: {})
            .padding(24)
    }
    .ignoresSafeArea()
    .havenReduceMotion()
}
