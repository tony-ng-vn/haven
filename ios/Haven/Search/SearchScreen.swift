import SwiftUI

/// Screen 6 of `../../phase1-build-plan.md`: search over the people you saved.
///
/// The field reads `people:searchDirectory` and the chips are filled from
/// `people:directoryFacets`, so both come from the caller's own directory
/// rather than a fixed list. An empty field is not an empty screen: the query
/// falls through to the most recent people, so opening search shows who you
/// saved last and typing narrows it.
struct SearchScreen: View {
    @StateObject private var model: SearchModel

    init() {
        _model = StateObject(wrappedValue: SearchModel())
    }

    /// A loaded screen that never opens a socket, for previews.
    init(
        preview load: SearchLoad,
        facets: DirectoryFacets = .empty,
        query: String = "",
        filters: SearchFilters = .any
    ) {
        _model = StateObject(
            wrappedValue: SearchModel(
                preview: load, facets: facets, query: query, filters: filters
            )
        )
    }

    var body: some View {
        HavenScreen(
            contentAlignment: .top,
            header: { header },
            content: { content },
            actions: { EmptyView() }
        )
        .navigationTitle("Search")
        // One read per settled key, not one per keystroke. Changing the key
        // cancels the sleep, so only the query someone stopped on is read.
        .task(id: model.key) {
            await model.searchAfterDebounce()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HavenField(
                label: "Search everyone",
                placeholder: "Search everyone",
                text: $model.query,
                capitalization: .never,
                submitLabel: .search
            )
            chips
        }
        .padding(.bottom, 4)
    }

    /// The chips the MVP search contract actually has, and only those.
    ///
    /// The prototype also offered month and context. Those describe when and
    /// where you met someone, which lives on the contacts table Phase 2
    /// creates, so a chip for either would be a filter over a field that does
    /// not exist. They are strong candidates once it does.
    private var chipDefinitions: [SearchChip] {
        [
            SearchChip(
                name: "Company",
                options: model.facets.companies,
                selection: $model.filters.company
            ),
            SearchChip(
                name: "City",
                options: model.facets.cities,
                selection: $model.filters.city
            ),
            SearchChip(
                name: "Role",
                options: model.facets.roles,
                selection: $model.filters.role
            ),
        ]
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chipDefinitions) { chip in
                    SearchChipView(chip: chip)
                }
            }
            // The row is inset by the screen's own margin, so the scroll view
            // gets that margin back as content padding or the first chip sits
            // on the edge when the row scrolls.
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            results
        }
    }

    /// One line reading back what the screen is showing.
    ///
    /// It holds its height whether or not it has anything to say, so the
    /// results below do not move down the moment it appears.
    private var summary: some View {
        Group {
            if case .ready(let people) = model.load, SearchRequest.isNarrowed(model.key) {
                Text(people.count == 1 ? "1 match" : "\(people.count) matches")
                    .havenSecondary()
            }
        }
        .frame(height: SearchMetrics.summaryLineHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var results: some View {
        switch model.load {
        case .loading:
            EmptyView()

        case .unreachable:
            VStack(spacing: 12) {
                Text("Could not reach your people.")
                    .havenSecondary()
                GhostButton(title: "Try again") { model.retry() }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 32)

        case .ready(let people) where people.isEmpty:
            // The two empty lists are different facts and get different
            // sentences: one is a search that found nobody, the other is a
            // directory nobody is in yet.
            Text(
                SearchRequest.isNarrowed(model.key)
                    ? "No one matches that."
                    : "Nobody saved yet. The people you meet land here."
            )
            .havenSecondary()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 32)

        case .ready(let people):
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(people) { person in
                    SearchResultRow(
                        name: person.name,
                        detail: person.detail,
                        query: model.query
                    )
                }
            }
        }
    }
}

enum SearchMetrics {
    /// One line of `havenSecondary` plus the gap under it. Held whether or not
    /// the line has anything to say.
    static let summaryLineHeight: CGFloat = 24
}

/// One filter chip: the dimension it narrows, what it can be set to, and where
/// its choice is kept.
private struct SearchChip: Identifiable {
    let name: String
    let options: [DirectoryFacets.Facet]
    let selection: Binding<String?>

    var id: String { name }
}

/// A chip that opens the values the caller's own directory actually holds.
///
/// Dim and inert when that dimension is empty. A chip offering nothing to
/// filter by is worse than a chip that says, by being dim, that there is
/// nothing behind it yet.
private struct SearchChipView: View {
    let chip: SearchChip

    private var isActive: Bool { chip.selection.wrappedValue != nil }

    var body: some View {
        Menu {
            Button("Any") { chip.selection.wrappedValue = nil }
            ForEach(chip.options) { option in
                Button("\(option.value) (\(option.count))") {
                    chip.selection.wrappedValue = option.value
                }
            }
        } label: {
            HStack(spacing: 5) {
                // Not havenSecondary(): it pins the colour to muted, and a set
                // chip has to read as set.
                Text(chip.selection.wrappedValue ?? chip.name)
                    .font(.footnote)
                    .foregroundStyle(isActive ? HavenColor.star : HavenColor.muted)
                if isActive {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HavenColor.star)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(
                isActive ? HavenColor.star.opacity(0.14) : HavenColor.fill,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isActive ? HavenColor.star.opacity(0.35) : HavenColor.hairline
                )
            )
        }
        .disabled(chip.options.isEmpty)
        .opacity(chip.options.isEmpty ? 0.5 : 1)
        .accessibilityLabel(chip.name)
        .accessibilityValue(chip.selection.wrappedValue ?? "Any")
        .accessibilityHint(
            chip.options.isEmpty
                ? "Nothing to filter by yet"
                : "Pick a \(chip.name.lowercased())"
        )
    }
}

/// One line of the results list: the person's name in serif with the matched
/// part lit, and what places them under it.
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

// Obviously-invented people, so nobody mistakes a preview for real data.
private let previewPeople = [
    DirectoryPerson(_id: "1", name: "Maya Chen", company: "Haven", role: "Founder", city: nil),
    DirectoryPerson(
        _id: "2", name: "Mai Nguyen", company: nil, role: nil, city: .init(name: "Da Nang")
    ),
    DirectoryPerson(
        _id: "3", name: "Ada Lovelace", company: nil, role: nil, city: .init(name: "London")
    ),
]

private let previewFacets = DirectoryFacets(
    companies: [.init(value: "Haven", count: 3)],
    cities: [.init(value: "Da Nang", count: 2), .init(value: "London", count: 1)],
    roles: [.init(value: "Founder", count: 1)]
)

#Preview("Search results") {
    NavigationStack {
        SearchScreen(preview: .ready(previewPeople), facets: previewFacets)
    }
}

#Preview("Search, nobody saved yet") {
    NavigationStack {
        SearchScreen(preview: .ready([]))
    }
}

#Preview("Search, unreachable") {
    NavigationStack {
        SearchScreen(preview: .unreachable)
    }
}

#Preview("Search, accessibility XXXL") {
    NavigationStack {
        SearchScreen(preview: .ready(previewPeople), facets: previewFacets)
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Search, Reduce Motion") {
    NavigationStack {
        SearchScreen(preview: .ready(previewPeople), facets: previewFacets)
    }
    .havenReduceMotion()
}
