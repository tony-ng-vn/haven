import SwiftUI

/// Screen 6 of `../../phase1-build-plan.md`: search, a shell in Phase 1.
///
/// The layout is real and the wiring is not. Phase 3 connects
/// `people:searchDirectory` behind it; until then the field types, the chips
/// sit disabled, and the results area says there is nothing to search yet. That
/// is the honest version of a screen whose data does not exist: it shows what
/// searching will look like without pretending to have done any.
struct SearchScreen: View {
    @State private var query = ""

    /// The chips the MVP search contract actually has, and only those.
    ///
    /// The prototype also offered month and context. Those describe when and
    /// where you met someone, which lives on the contacts table Phase 2
    /// creates, so a chip for either would be a filter over a field that does
    /// not exist. They are strong Phase 3 candidates once it does.
    private static let filters = ["Company", "City", "Role"]

    var body: some View {
        HavenScreen(
            contentAlignment: .top,
            header: { header },
            content: { content },
            actions: { EmptyView() }
        )
        .navigationTitle("Search")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HavenField(
                label: "Search everyone",
                placeholder: "Search everyone",
                text: $query,
                capitalization: .never,
                submitLabel: .search
            )
            chips
        }
        .padding(.bottom, 4)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Self.filters, id: \.self) { filter in
                    Text(filter)
                        .havenSecondary()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(HavenColor.fill, in: Capsule())
                        .overlay(Capsule().strokeBorder(HavenColor.hairline))
                }
            }
            // The row is inset by the screen's own margin, so the scroll view
            // gets that margin back as content padding or the first chip sits
            // on the edge when the row scrolls.
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        // Not buttons yet. A chip that opens nothing is worse than a chip that
        // says, by being dim, that it is not ready.
        .disabled(true)
        .opacity(0.5)
        .accessibilityLabel("Filters: company, city, role")
        .accessibilityHint("Not available yet")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The interp line goes here: one line reading back what a query was
            // understood to mean. Phase 3's fast-follow builds it, and the
            // prototype's version was a faked preview of it. The slot is kept
            // so the results below do not move down the day it arrives.
            Color.clear
                .frame(height: SearchMetrics.interpLineHeight)
                .accessibilityHidden(true)

            Text(query.isEmpty ? "Search is not wired up yet." : "Nothing to search yet.")
                .havenSecondary()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 32)
        }
    }
}

enum SearchMetrics {
    /// One line of `havenSecondary` plus the gap under it. Reserved, not drawn.
    static let interpLineHeight: CGFloat = 24
}

/// One line of the results list: the person's name in serif with the matched
/// part lit, and what places them under it.
///
/// Built now and unused by the screen above on purpose. Phase 3 supplies the
/// results; this is the row it will supply them to, and it is where the look of
/// a result is decided rather than in the wiring.
struct SearchResultRow: View {
    let name: String
    var detail: String?
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MatchHighlight.attributed(name, matching: query))
                .personName(.row)
                .foregroundStyle(HavenColor.ink)
            if let detail, !detail.isEmpty {
                Text(MatchHighlight.attributed(detail, matching: query))
                    .havenSecondary()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 8)
        // The highlight is colour and weight, which a screen reader gets
        // nothing from, so it reads the plain line.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, detail].compactMap { $0 }.joined(separator: ", "))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HavenColor.hairline)
                .frame(height: 1)
        }
    }
}

// MARK: - Previews

#Preview("Search") {
    NavigationStack {
        SearchScreen()
    }
}

#Preview("Search, accessibility XXXL") {
    NavigationStack {
        SearchScreen()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Search, Reduce Motion") {
    NavigationStack {
        SearchScreen()
    }
    .havenReduceMotion()
}

// What Phase 3 will render. Obviously-invented people, so nobody mistakes a
// preview for real data.
#Preview("Search results, Phase 3 shape") {
    ZStack {
        NightBackground()
        VStack(alignment: .leading, spacing: 0) {
            SearchResultRow(name: "Maya Chen", detail: "Founder, Haven", query: "ma")
            SearchResultRow(name: "Mai Nguyen", detail: "Da Nang", query: "ma")
            SearchResultRow(name: "Ada Lovelace", detail: "London", query: "ma")
        }
        .padding(24)
    }
    .ignoresSafeArea()
}
