import Foundation

/// What `people:saveSharedProfile` answers.
struct SharedProfileOutcome: Decodable, Equatable, Sendable {
    let status: String
    let personId: String
    /// True when the context cap cut the note. The capture landed, but not all
    /// of it, and the drain is the only thing that ever finds out.
    let noteTruncated: Bool
}

/// Where a drained capture goes.
///
/// A protocol so the loop below can be tested without a deployment. The real
/// one is `ConvexCaptureSink`; it is the only part of this that talks to the
/// network.
protocol CaptureSink: Sendable {
    func saveProfile(_ profile: QueuedCapture.Profile) async throws -> SharedProfileOutcome
    func saveScreenshot(_ image: Data) async throws
    func saveManual(_ manual: QueuedCapture.Manual) async throws -> SharedProfileOutcome
}

/// What one pass of the drain did.
struct DrainResult: Equatable, Sendable {
    var sent = 0
    /// Could not be sent this time, still waiting. Almost always no network.
    var kept = 0
    /// Could never be sent, so keeping it would mean retrying forever.
    var dropped = 0
    /// Saves whose note was clipped at the cap.
    ///
    /// Counted and, for v1, deliberately not shown -- settled in wave G4 of the
    /// frontend completion plan. The drain is the only thing that ever learns a
    /// note was clipped, and it learns it long after the sheet closed, often on
    /// a launch the person did not connect to the capture. There is no queue
    /// screen to carry the news to, and inventing one to deliver it would be a
    /// second place to look for something that already landed. The person did
    /// land, with four thousand characters of what was written about them.
    ///
    /// It stays counted rather than dropped because the day there is a surface
    /// -- a triage screen, a capture log -- this is what it reads.
    var truncatedNotes = 0
}

/// Sends everything the share extension queued while the app was not running.
///
/// One mutation per item rather than one batch. Queues are small -- a handful
/// of captures per event -- and a batch in Convex is all-or-nothing unless
/// every item runs as its own caught subtransaction, which is complexity with
/// no payoff at this size.
///
/// Every item is attempted independently: one the server will not take must
/// not strand the ones behind it, or a single bad capture quietly blocks the
/// queue for the life of the install.
struct CaptureDrain {
    let queue: CaptureQueue
    let sink: CaptureSink
    /// How long one item's send may run before this loop gives up on it and
    /// moves to the next.
    ///
    /// `ConvexCaptureSink` already bounds its own mutations, but this is the
    /// backstop: `CaptureSync.run()`'s `isRunning` guard only resets once
    /// `run()` itself returns, so a sink that hangs on any one item -- bounded
    /// or not -- would otherwise stall this whole loop and, with it, every
    /// capture sync for the rest of the session. Overridable so a test that
    /// models a sink whose call never returns does not itself wait out the
    /// real deadline.
    var deadline: TimeInterval = HavenNetwork.deadline

    func run() async -> DrainResult {
        var result = DrainResult()
        for capture in queue.pending() {
            switch capture.payload {
            case .profile(let profile):
                do {
                    let outcome = try await bounded { try await sink.saveProfile(profile) }
                    if outcome.noteTruncated { result.truncatedNotes += 1 }
                    try? queue.remove(capture)
                    result.sent += 1
                } catch {
                    // Kept, not dropped: the usual reason is that there was no
                    // network, and losing the capture is the one outcome the
                    // whole queue exists to prevent.
                    result.kept += 1
                }
            case .manual(let manual):
                do {
                    let outcome = try await bounded { try await sink.saveManual(manual) }
                    if outcome.noteTruncated { result.truncatedNotes += 1 }
                    try? queue.remove(capture)
                    result.sent += 1
                } catch {
                    // Kept for the same reason a shared profile is: the usual
                    // reason is no network, and a person somebody typed out by
                    // hand exists nowhere else yet.
                    result.kept += 1
                }
            case .screenshot(let screenshot):
                let url = queue.imageURL(named: screenshot.fileName)
                // Off the calling actor: CaptureSync.run() is @MainActor, and
                // this loop is otherwise called straight from it with nothing
                // in between to hop off the main thread for a plain
                // synchronous disk read.
                guard let image = await Self.readImage(at: url) else {
                    // The image is gone, so this can never be uploaded.
                    // Keeping it would retry it on every launch forever.
                    try? queue.remove(capture)
                    result.dropped += 1
                    continue
                }
                do {
                    try await bounded { try await sink.saveScreenshot(image) }
                    try? queue.remove(capture)
                    result.sent += 1
                } catch {
                    result.kept += 1
                }
            }
        }
        return result
    }

    private func bounded<Value>(_ call: @escaping () async throws -> Value) async throws -> Value {
        let work = Task { try await call() }
        guard let value = await work.value(within: .seconds(deadline)) else {
            throw DrainError.timedOut
        }
        return value
    }

    private static func readImage(at url: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            try? Data(contentsOf: url)
        }.value
    }

    enum DrainError: Error {
        case timedOut
    }
}
