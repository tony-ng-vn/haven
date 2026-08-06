import Combine
import ConvexMobile
import SwiftUI

/// A request to send whatever capture is waiting, now rather than at the next
/// launch.
///
/// An environment value rather than a closure threaded down through the view
/// tree: nothing between the root and the add sheet -- onboarding, the tabs,
/// the directory list -- has any business knowing the capture queue exists, and
/// passing one through each of them would teach every one of them that it does.
/// The default does nothing, so a preview renders without a Convex client
/// behind it.
struct CaptureDrainRequest {
    var run: () async -> Void = {}
}

private struct CaptureDrainRequestKey: EnvironmentKey {
    static let defaultValue = CaptureDrainRequest()
}

extension EnvironmentValues {
    var requestCaptureDrain: CaptureDrainRequest {
        get { self[CaptureDrainRequestKey.self] }
        set { self[CaptureDrainRequestKey.self] = newValue }
    }
}

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
    ///
    /// `userId` scopes `HandleDropState` the same way it scopes
    /// `ContactChangeState`: two accounts on one device must never see each
    /// other's dropped-handle notice. Taken here rather than at `init`,
    /// because this type is constructed once, eagerly, in `RootView`, before
    /// Clerk has resolved who is signed in -- every real call site already
    /// has it in hand by the time it calls this.
    func run(userId: String) async {
        // Re-entrant calls are the normal case, not a bug: a launch and a
        // foreground can land together. The second one would replay captures
        // the first has not deleted yet, and the server would answer "already"
        // to every one of them.
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let handleDrops = HandleDropState(userId: userId)
        // Z1: CaptureDrain's own struct-level default for this is scoped to
        // a throwaway random id -- exactly wrong here, where a conflict
        // notice must be suppressed on the *next* run(userId:) call, not
        // just within this one. This is the one line that makes the
        // suppression real rather than only passing in CaptureDrainTests.
        let conflictMarks = ConflictNoticeMarks(userId: userId)
        for queue in queues {
            let result = await CaptureDrain(queue: queue, sink: sink, conflictMarks: conflictMarks).run()
            // Recorded in the order they happened -- HandleDropState now
            // queues rather than overwrites, so a handle-cap drop and a
            // final conflict landing in the same pass both reach whoever is
            // watching, oldest first, instead of the second silently
            // erasing the first. record(_:) itself posts the notification
            // that lets an already-open DirectoryScreen pick this up without
            // waiting for its own next foreground.
            for event in result.notices {
                handleDrops.record(event)
            }
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
    ///
    /// Not `private`: `DirectoryPagingTests` reads it to pin the wire shape
    /// against the same value this file sends, the way `Config`'s keys are
    /// widened for `ConfigTests`.
    static let mirrorSize: Double = 500
}
