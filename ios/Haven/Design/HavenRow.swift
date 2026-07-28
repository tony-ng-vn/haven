import SwiftUI

/// A list line: optional leading glyph, a title with an optional detail line, and
/// a trailing accessory. Used for the connect-an-account rows, city suggestions,
/// people, and the edit screen's fields.
///
/// The whole row is one VoiceOver element and one hit target, because a row where
/// the glyph, the name and the chevron announce separately is three times the
/// work to get through.
struct HavenRow<Leading: View, Trailing: View>: View {
    let title: String
    var detail: String?
    /// Overrides what VoiceOver reads. Defaults to the title plus the detail.
    var accessibilityText: String?
    /// Colours the title as a warning. For rows that take something away, so
    /// deleting an account does not look like editing a job title.
    var isDestructive = false
    var action: (() -> Void)?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(RowPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText)
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText)
        }
    }

    private var spokenText: String {
        accessibilityText ?? [title, detail].compactMap { $0 }.joined(separator: ", ")
    }

    private var content: some View {
        HStack(spacing: 11) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .havenBody(isDestructive ? HavenColor.ember : HavenColor.ink)
                if let detail {
                    Text(detail)
                        .havenSecondary()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
        // A one-line row at the smallest text size otherwise lands under the
        // 44pt minimum tap target.
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HavenColor.hairline)
                .frame(height: 1)
        }
    }
}

extension HavenRow where Leading == EmptyView {
    init(
        title: String,
        detail: String? = nil,
        accessibilityText: String? = nil,
        isDestructive: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            detail: detail,
            accessibilityText: accessibilityText,
            isDestructive: isDestructive,
            action: action,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

extension HavenRow where Leading == EmptyView, Trailing == EmptyView {
    init(
        title: String,
        detail: String? = nil,
        accessibilityText: String? = nil,
        isDestructive: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            detail: detail,
            accessibilityText: accessibilityText,
            isDestructive: isDestructive,
            action: action,
            leading: { EmptyView() },
            trailing: { EmptyView() }
        )
    }
}

/// Rows highlight rather than scale: a row inside a list that shrinks drags its
/// neighbours' separators with it.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? HavenColor.rowHighlight : .clear)
            .havenAnimation(HavenMotion.press, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// The trailing text on a row: a call to action while empty, the committed value
/// once it is set.
struct RowAccessory: View {
    let text: String
    var isSet = false

    var body: some View {
        Text(text)
            .font(.footnote)
            // `muted` rather than `faint` for the same reason the group labels
            // moved: `faint` is 3.40:1 over dusk, and these sit low on the page
            // where the background is dusk-ward.
            .foregroundStyle(isSet ? HavenColor.star : HavenColor.muted)
            .lineLimit(1)
    }
}

/// The mark on a row that opens something.
///
/// `HavenRow` already hands VoiceOver the `.isButton` trait, so without this
/// the screen reader is told more than the eye is: six rows that all open a
/// sheet, and nothing but the press highlight saying so.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(HavenColor.muted)
            .accessibilityHidden(true)
    }
}

#Preview("Rows") {
    ZStack {
        NightBackground()
        VStack(alignment: .leading, spacing: 0) {
            Text("Connect an account").havenGroupLabel()
                .padding(.bottom, 5)
            HavenRow(title: "Instagram", action: {}) {
                RowAccessory(text: "Connect")
            }
            HavenRow(title: "X", accessibilityText: "X, connected as tonynguyen", action: {}) {
                RowAccessory(text: "@tonynguyen", isSet: true)
            }
            Text("Or type one").havenGroupLabel()
                .padding(.top, 15)
                .padding(.bottom, 5)
            HavenRow(title: "Phone", action: {}) {
                RowAccessory(text: "Add")
            }
            HavenRow(title: "Ho Chi Minh City", detail: "Vietnam", action: {})
        }
        .padding(24)
    }
}
