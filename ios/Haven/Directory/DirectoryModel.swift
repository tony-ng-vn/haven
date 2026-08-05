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

/// Reads the caller's directory, a page at a time as the list is scrolled.
///
/// The window grows rather than the cursors chaining, and that is the decision
/// worth knowing. Every page has to stay live -- a person edited on another
/// device, or one the drain just landed, should change in this list without a
/// relaunch -- and a cursor chain means one subscription per page, N of them
/// open, with the pages stitched back together in order on every update. Asking
/// for more rows from the one subscription is the same data, live, with nothing
/// to stitch. It re-reads what it already had, which for a directory measured in
/// hundreds is cheaper than the machinery it replaces.
@MainActor
final class DirectoryModel: ObservableObject {
    @Published private(set) var load: DirectoryLoad = .loading

    /// True from asking for more rows until they arrive. Published because the
    /// list says so at its foot rather than ending on nothing, and read here to
    /// stop a list that scrolls past its own end asking twice.
    @Published private(set) var isLoadingMore = false

    /// How many rows the current subscription asks for.
    ///
    /// A `Double`, not an `Int`: ConvexEncodable wraps a `FixedWidthInteger` as
    /// `{"$integer": base64}`, and `paginationOptsValidator` on the server
    /// types `numItems` as `v.number()` -- a float64 that refuses that
    /// wrapper. Sent as an `Int` this reads perfectly and fails validation on
    /// every call.
    private(set) var window = DirectoryModel.pageSize

    private var cancellable: AnyCancellable?
    /// False for the preview and test model, which has its pages handed to it.
    /// Paging is decided here and only the reading of it needs a deployment.
    private let isLive: Bool

    /// How many more rows each scroll to the end asks for. Comfortably more
    /// than most directories hold, so most people never page at all.
    private static let pageSize: Double = 50

    init() {
        isLive = true
        subscribe()
    }

    /// A loaded directory that never opens a socket, for previews and tests.
    init(preview load: DirectoryLoad) {
        isLive = false
        self.load = load
    }

    var people: [DirectoryPerson] {
        if case .ready(let page) = load { return page.page }
        return []
    }

    /// True once the directory has answered and holds nobody.
    ///
    /// Distinct from `people.isEmpty`, which is also true while the read is in
    /// flight: a suggestion that flashed up during loading and vanished when
    /// the first page landed would be worse than one that waits a beat.
    var isEmpty: Bool {
        if case .ready(let page) = load { return page.page.isEmpty }
        return false
    }

    func retry() {
        load = .loading
        subscribe()
    }

    /// Asks for another page.
    ///
    /// Called by the last row appearing, which is the only honest trigger: a
    /// scroll offset would have to guess at row heights, and rows here are as
    /// tall as somebody's text size makes them.
    func loadMore() {
        guard case .ready(let page) = load, !page.isDone, !isLoadingMore else { return }
        isLoadingMore = true
        window += Self.pageSize
        subscribe()
    }

    private func subscribe() {
        guard isLive else { return }
        let options: [String: ConvexEncodable?] = [
            "numItems": window,
            // Always the first page. The window is what grows; a cursor here
            // would ask for the rows *after* it and lose the ones already on
            // screen.
            "cursor": nil,
        ]
        cancellable = HavenNetwork.subscribe(
            to: "people:listPeople",
            with: ["paginationOpts": options],
            yielding: DirectoryPage.self
        ) { [weak self] page in
            guard let self else { return }
            self.isLoadingMore = false
            self.load = .ready(page)
        } onSilence: { [weak self] in
            guard let self else { return }
            self.isLoadingMore = false
            // A read for more rows that never answers leaves the rows already
            // on screen alone: the list is not broken, it just did not grow.
            guard self.load == .loading else { return }
            self.load = .unreachable
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
