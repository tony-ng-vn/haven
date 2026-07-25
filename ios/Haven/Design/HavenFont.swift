import SwiftUI

// Type is expressed as view modifiers rather than raw `Font` values, for one
// reason: it keeps `.serif` inside this file.
//
// THE RULE: serif (New York) is reserved for people's names. Questions,
// buttons, labels and every other piece of UI use SF Pro. This single rule is
// what stops Haven reading as a meditation app. `personName(_:)` below is the
// only serif surface in the app -- a grep for "serif" outside this file should
// return nothing. If a new text role needs a style, add a modifier here in SF
// Pro; do not add a second serif case.
//
// Every style is built from a relative text style (.title, .footnote, and so
// on) rather than a point size, so Dynamic Type scales all of it for free.

/// How large a person's name is rendered. Names are the only serif text, so
/// their sizes live together.
enum PersonNameScale {
    /// The card and the beacon: the name is the subject of the screen.
    case card
    /// A search result or directory row.
    case row
    /// Initials inside a small avatar circle.
    case avatar

    fileprivate var font: Font {
        switch self {
        case .card: return .system(.title, design: .serif)
        case .row: return .system(.body, design: .serif)
        case .avatar: return .system(.subheadline, design: .serif).weight(.semibold)
        }
    }
}

extension View {
    /// A person's name. The only serif text in Haven.
    func personName(_ scale: PersonNameScale = .card) -> some View {
        font(scale.font)
    }

    /// The "Haven" wordmark on the welcome screen.
    func havenWordmark() -> some View {
        font(.system(.title, weight: .semibold))
            .tracking(HavenFont.tightTracking)
            .foregroundStyle(HavenColor.ink)
    }

    /// An onboarding question. One per screen, pinned top.
    func havenQuestion() -> some View {
        font(.system(.title2, weight: .semibold))
            .tracking(HavenFont.tightTracking)
            .foregroundStyle(HavenColor.ink)
    }

    /// The line under a question that sets expectations ("City only. Never your
    /// street address.").
    func havenHint() -> some View {
        font(.footnote)
            .foregroundStyle(HavenColor.muted)
    }

    /// Default running text and row titles.
    func havenBody() -> some View {
        font(.subheadline)
            .foregroundStyle(HavenColor.ink)
    }

    /// Supporting text beside or beneath something else.
    func havenSecondary() -> some View {
        font(.footnote)
            .foregroundStyle(HavenColor.muted)
    }

    /// A group heading over a list of rows ("Connect an account").
    func havenGroupLabel() -> some View {
        font(.system(.caption2, weight: .semibold))
            .tracking(HavenFont.wideTracking)
            .textCase(.uppercase)
            .foregroundStyle(HavenColor.faint)
    }

    /// Machine-shaped text: the beacon address, a phone number.
    func havenMono() -> some View {
        font(.system(.footnote, design: .monospaced))
            .foregroundStyle(HavenColor.star)
    }
}

enum HavenFont {
    /// Headlines are set slightly tight, which is what keeps them from reading
    /// as system alerts.
    static let tightTracking: CGFloat = -0.4
    /// All-caps labels need the opposite treatment or they set as a block.
    static let wideTracking: CGFloat = 1

    /// Used by `PrimaryButton`.
    static let buttonLabel: Font = .system(.subheadline, weight: .semibold)
    /// Used by `GhostButton`.
    static let ghostLabel: Font = .footnote
}

#Preview("Type scale") {
    ZStack {
        NightBackground()
        VStack(alignment: .leading, spacing: 14) {
            Text("Haven").havenWordmark()
            Text("What is your name?").havenQuestion()
            Text("City only. Never your street address.").havenHint()
            Text("This is body text on a row.").havenBody()
            Text("Secondary support text.").havenSecondary()
            Text("Connect an account").havenGroupLabel()
            Text("inhavens.com/tony").havenMono()
            Divider().overlay(HavenColor.hairline)
            Text("Serif is names only:").havenSecondary()
            Text("Tony Nguyen").personName(.card)
            Text("Tony Nguyen").personName(.row)
            Text("TN").personName(.avatar)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}

// The style most likely to break silently: if a name stops scaling, this
// preview looks identical to the default-size one.
#Preview("Type scale, accessibility XXXL") {
    ZStack {
        NightBackground()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("What is your name?").havenQuestion()
                Text("City only. Never your street address.").havenHint()
                Text("Tony Nguyen").personName(.card)
                Text("Tony Nguyen").personName(.row)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
