import Combine
import ConvexMobile
import SwiftUI

/// One saved person, as `people:listPeople` returns them. The query sends more
/// than this; the directory shell shows a name and one line under it, and an
/// unknown key is ignored.
struct DirectoryPerson: Decodable, Equatable, Identifiable {
    let _id: String
    let name: String
    var company: String?
    var role: String?
    var city: City?

    var id: String { _id }

    struct City: Decodable, Equatable {
        let name: String
    }

    /// The line under the name: what this person does, or where they are.
    /// Whichever exists; nothing at all is a name on its own, which is honest.
    var detail: String? {
        let work = [role, company].compactMap { $0 }.filter { !$0.isEmpty }
        if !work.isEmpty { return work.joined(separator: ", ") }
        return city?.name
    }
}

/// One page of `people:listPeople`, which is Convex's standard pagination shape.
struct DirectoryPage: Decodable, Equatable {
    let page: [DirectoryPerson]
    let isDone: Bool
}

/// Whether the directory knows what it holds yet.
enum DirectoryLoad: Equatable {
    case loading
    case ready(DirectoryPage)
    /// The directory could not be read. Said out loud with a way to try again,
    /// because a spinner that never ends is the one outcome with no way out.
    case unreachable
}

/// Reads the first page of the caller's directory.
///
/// One page, not the whole list: Phase 1 needs a count and an empty state, and
/// the listing UX that would justify paging arrives in Phase 2.
@MainActor
final class DirectoryModel: ObservableObject {
    @Published private(set) var load: DirectoryLoad = .loading

    private var cancellable: AnyCancellable?

    /// How many people the first page asks for. Comfortably more than a Phase 1
    /// directory holds, so the count it drives is usually the whole truth.
    private static let pageSize = 50

    /// Long enough for a slow connection, short enough that a dead one does not
    /// hold the screen. The same bound onboarding's card read uses.
    private static let networkDeadline: TimeInterval = 12

    init() {
        subscribe()
    }

    /// A loaded directory that never opens a socket, for previews.
    init(preview load: DirectoryLoad) {
        self.load = load
    }

    var people: [DirectoryPerson] {
        if case .ready(let page) = load { return page.page }
        return []
    }

    /// How many people to say there are.
    ///
    /// Nil while loading or unreachable, because a count of zero and a count we
    /// could not read are different things and only one of them is "nobody".
    var count: Int? {
        if case .ready(let page) = load { return page.page.count }
        return nil
    }

    /// True when the first page filled up and there are more behind it, so the
    /// count is a floor rather than a total.
    var countIsPartial: Bool {
        if case .ready(let page) = load { return !page.isDone }
        return false
    }

    func retry() {
        load = .loading
        subscribe()
    }

    private func subscribe() {
        let options: [String: ConvexEncodable?] = [
            "numItems": Self.pageSize,
            "cursor": nil,
        ]
        cancellable = convex
            .subscribe(
                to: "people:listPeople",
                with: ["paginationOpts": options],
                yielding: DirectoryPage.self
            )
            // The Convex client reconnects rather than failing, so a read with
            // no network does not error, it waits. Nothing else would end that
            // wait.
            .timeout(.seconds(Self.networkDeadline), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Any ending counts, not just a failure: a timeout finishes the
                // stream without a value, so still being in `.loading` here is
                // what "we never heard back" looks like.
                guard let self, self.load == .loading else { return }
                self.load = .unreachable
            } receiveValue: { [weak self] page in
                self?.load = .ready(page)
            }
    }
}

/// Whether this person has dismissed the Lock Screen widget card.
///
/// Kept on the device rather than on the card: dismissing a suggestion is a
/// fact about this phone's home screen, not about who someone is. Keyed by user
/// so a second account on the same phone sees the card fresh, the same way
/// `OnboardingSkips` is.
enum WidgetPromoDismissal {
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
        "haven.directory.widgetPromoDismissed.\(userId)"
    }
}
