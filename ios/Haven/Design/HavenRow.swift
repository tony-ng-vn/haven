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
                    .havenBody()
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            detail: detail,
            accessibilityText: accessibilityText,
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
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            detail: detail,
            accessibilityText: accessibilityText,
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
            .foregroundStyle(isSet ? HavenColor.star : HavenColor.faint)
            .lineLimit(1)
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
