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
        VStack(alignment: .leading, spacing: 6) {
            Text("Your beacon, one tap from the Lock Screen")
                .havenBody()
                // Room for the dismiss target, which floats over the card
                // rather than sitting in this stack: at 44pt it would set the
                // height of the whole first line.
                .padding(.trailing, 28)
            Text("Add the widget and your code is there when you need it.")
                .havenSecondary()
            Button(action: open) {
                Text("See how")
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
