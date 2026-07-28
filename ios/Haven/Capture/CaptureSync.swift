import Combine
import ConvexMobile
import SwiftUI

/// A person as the mirror needs them, straight off `people:listPeople`.
///
/// Its own shape rather than `DirectoryPerson`: the directory screen shows a
/// name and a line under it, and the share sheet needs the handles instead.
private struct MirrorSource: Decodable {
    let _id: String
    let name: String
    let contactHandles: [Handle]?

    struct Handle: Decodable {
        let platform: String
        let value: String
    }
}

private struct MirrorPage: Decodable {
    let page: [MirrorSource]
}

/// Drains what the share extension captured, then leaves it a fresh copy of
/// the directory to read.
///
/// Runs on launch and whenever the app comes back to the foreground, because
/// those are exactly the moments somebody has just finished sharing and
/// switched back. Nothing is shown while it works: a capture that landed is
/// a person in the directory, and a queue screen would be a second place to
/// look for something that is already where it belongs.
@MainActor
final class CaptureSync: ObservableObject {
    private let queues: [CaptureQueue]
    private let mirror: DirectoryMirrorStore?
    private let sink: CaptureSink
    private var isRunning = false
    private var cancellable: AnyCancellable?

    init(
        queues: [CaptureQueue] = CaptureQueue.drainable(),
        mirror: DirectoryMirrorStore? = DirectoryMirrorStore.forApp(),
        sink: CaptureSink = ConvexCaptureSink()
    ) {
        self.queues = queues
        self.mirror = mirror
        self.sink = sink
    }

    /// One pass: send what is waiting, then refresh the mirror.
    ///
    /// The mirror is refreshed even when the queue was empty, because it is
    /// what the *next* share reads to offer "add to an existing person", and
    /// it goes stale on its own as the directory changes elsewhere.
    func run() async {
        // Re-entrant calls are the normal case, not a bug: a launch and a
        // foreground can land together. The second one would replay captures
        // the first has not deleted yet, and the server would answer "already"
        // to every one of them.
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        for queue in queues {
            _ = await CaptureDrain(queue: queue, sink: sink).run()
        }
        await refreshMirror()
    }

    /// Writes the extension's copy of the directory.
    ///
    /// A cache and only a cache: it can be days stale if nobody opens the app,
    /// which is why the drain reconciles on the server rather than trusting
    /// what the sheet decided from it.
    private func refreshMirror() async {
        guard let mirror else { return }
        guard let page = await firstPage() else { return }
        let people = page.page.map { person in
            MirrorPerson(
                id: person._id,
                name: person.name,
                handles: (person.contactHandles ?? []).map {
                    MirrorHandle(platform: $0.platform, value: $0.value)
                }
            )
        }
        try? mirror.save(DirectoryMirror(refreshedAt: Date(), people: people))
    }

    /// The most recent page of the directory, or nil if the read never
    /// answered.
    ///
    /// One page, in the order `listPeople` returns it -- most recently updated
    /// first -- so when the sheet has more matches than fit, the ones it drops
    /// are the ones least likely to be who you just met.
    private func firstPage() async -> MirrorPage? {
        await withCheckedContinuation { continuation in
            var resumed = false
            cancellable = HavenNetwork.subscribe(
                to: "people:listPeople",
                with: ["paginationOpts": ["numItems": Self.mirrorSize, "cursor": nil]],
                yielding: MirrorPage.self,
                firstValueOnly: true,
                onValue: { page in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: page)
                },
                onSilence: {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: nil)
                }
            )
        }
    }

    /// How many people the extension can offer. Comfortably more than a
    /// Phase 2 directory holds, and the sheet searches by name rather than
    /// scrolling, so a bigger mirror would only cost the extension memory it
    /// does not have.
    private static let mirrorSize = 500
}
