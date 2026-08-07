import SwiftUI

struct ActiveEventCard: View {
    let event: HavenEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HavenColor.star)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Event mode")
                    .havenGroupLabel()
                Text(event.title)
                    .havenBody()
                    .foregroundStyle(HavenColor.ink)
                Text("Everyone you save now is added to this event.")
                    .havenSecondary()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HavenColor.fill, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(HavenColor.star.opacity(0.24))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Event mode, \(event.title). Everyone you save now is added to this event.")
    }
}

/// The global Event Mode reminder on screens where saving still happens but
/// the full People card would take over the task somebody came here to do.
struct EventModeBanner: View {
    let event: EventReference

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HavenColor.star)
                .accessibilityHidden(true)
            Text("Adding to \(event.title)")
                .havenSecondary(HavenColor.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HavenColor.fill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(HavenColor.star.opacity(0.24))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Event mode. Adding people to \(event.title).")
    }
}
