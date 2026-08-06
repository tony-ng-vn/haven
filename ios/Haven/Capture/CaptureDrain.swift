import Foundation
import os

/// What `people:saveSharedProfile` answers.
struct SharedProfileOutcome: Decodable, Equatable, Sendable {
    let status: String
    let personId: String
    /// True when the context cap cut the note. The capture landed, but not all
    /// of it, and the drain is the only thing that ever finds out.
    let noteTruncated: Bool
    /// True when the account this capture named could not fit under the
    /// 8-handle cap on the person it landed on. `var` with a default rather
    /// than `let`: a `let` with a default value is dropped from Swift's
    /// memberwise init entirely, which would make it uninitializable to
    /// `true` from a test. Surfaced to the person saving it -- see
    /// `HandleDropState` and `DrainResult.notices` -- and logged for
    /// Console.app either way.
    var handleDropped = false
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

/// Whether a `saveSharedProfile` outcome should be resubmitted once, with
/// `attachToPersonId` cleared.
///
/// Only "conflict" ever needs it, and only when the capture actually asked to
/// attach to somebody: that is the one conflict a resubmit can fix, because
/// the refusal came from the caller's own attach guess losing to handle
/// identity (see `saveSharedProfile` in convex/people.ts), and stripping the
/// guess lets handle identity route the note to the true owner instead --
/// the pre-conflict-era behavior, and it loses nothing.
///
/// A capture with no attach guess at all can still come back "conflict" --
/// its handle's stored value already belongs to somebody else, from
/// `mergeHandleIntoOwner`'s "refused" branch -- but nothing about a plain
/// resubmit would change that answer, so this never retries it. `run()`
/// treats that the same as a resubmit that conflicts a second time: a final
/// conflict, kept rather than sent.
enum ConflictRetry {
    static func shouldRetry(_ outcome: SharedProfileOutcome, hadAttachToPersonId: Bool) -> Bool {
        hadAttachToPersonId && outcome.status == "conflict"
    }
}

extension QueuedCapture.Profile {
    /// The same capture with `attachToPersonId` cleared, for `ConflictRetry`'s
    /// one resubmit.
    fileprivate var strippingAttach: Self {
        Self(link: link, profileUrl: profileUrl, name: name, note: note, attachToPersonId: nil)
    }
}

extension QueuedCapture.Manual {
    /// The same capture with `attachToPersonId` cleared, for `ConflictRetry`'s
    /// one resubmit.
    fileprivate var strippingAttach: Self {
        Self(
            name: name, platform: platform, handleValue: handleValue, profileUrl: profileUrl,
            note: note, attachToPersonId: nil, source: source, platformId: platformId
        )
    }
}

/// What one pass of the drain did.
struct DrainResult: Equatable, Sendable {
    var sent = 0
    /// Could not be sent this time, still waiting -- no network, or a final
    /// conflict (see `ConflictRetry`) that landed nowhere. Either way the
    /// queue item is the one copy of what was written, and it stays.
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
    /// Every capture this pass that needs a user-visible notice -- a handle
    /// dropped at the cap, or a final conflict that landed nowhere -- in the
    /// order they happened. `CaptureSync.run(userId:)` is what actually
    /// records these into `HandleDropState` -- this only reports what
    /// happened, the same separation `CaptureSink` draws between deciding
    /// and doing.
    var notices: [HandleDropState.Event] = []
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

    /// Which queued captures have already told the person about a conflict,
    /// so a later pass that replays the same unresolved conflict does not
    /// notify again. `CaptureSync.run(userId:)` -- the only production
    /// caller -- always constructs its own scoped to the real signed-in
    /// `userId`; this struct-level default, scoped to a fresh random id
    /// instead, exists only so the tests that do not care about conflict
    /// bookkeeping can build a `CaptureDrain` without one. It can never see
    /// another instance's marks, so it also never suppresses a repeat --
    /// correct for those tests, and exactly why production never relies on
    /// it.
    var conflictMarks = ConflictNoticeMarks(userId: UUID().uuidString)

    /// A Console.app breadcrumb for a dropped handle, alongside the
    /// user-visible one `DrainResult.notices` carries back to `CaptureSync`.
    /// The note still landed on the person either way, and the queue still
    /// clears -- neither of those changes. A final conflict gets no matching
    /// breadcrumb here: `process(...)` returns before this would run, since
    /// nothing landed for it to log about.
    private static let logger = Logger(subsystem: "com.inhavens.haven", category: "capture")

    func run() async -> DrainResult {
        var result = DrainResult()
        for capture in queue.pending() {
            switch capture.payload {
            case .profile(let profile):
                await process(
                    captureId: capture.id,
                    hadAttachToPersonId: profile.attachToPersonId != nil,
                    displayName: profile.name,
                    platform: profile.link.platform.rawValue,
                    into: &result,
                    remove: { try? queue.remove(capture) },
                    send: { try await bounded { try await sink.saveProfile(profile) } },
                    resend: { try await bounded { try await sink.saveProfile(profile.strippingAttach) } }
                )
            case .manual(let manual):
                await process(
                    captureId: capture.id,
                    hadAttachToPersonId: manual.attachToPersonId != nil,
                    displayName: manual.name,
                    platform: manual.platform,
                    into: &result,
                    remove: { try? queue.remove(capture) },
                    send: { try await bounded { try await sink.saveManual(manual) } },
                    resend: { try await bounded { try await sink.saveManual(manual.strippingAttach) } }
                )
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

    /// Sends one shared-profile or manual capture, resubmitting once on a
    /// retryable conflict, and folds whatever comes back into `result`.
    ///
    /// Shared by both `.profile` and `.manual`: the payloads differ, but what
    /// happens to their answer -- retry once, then land, keep, or report --
    /// does not, and Y1's fix needed both branches to treat a final conflict
    /// identically, which is what made keeping only one copy of this worth
    /// doing.
    private func process(
        captureId: UUID,
        hadAttachToPersonId: Bool,
        displayName: String,
        platform: String,
        into result: inout DrainResult,
        remove: () -> Void,
        send: () async throws -> SharedProfileOutcome,
        resend: () async throws -> SharedProfileOutcome
    ) async {
        do {
            var outcome = try await send()
            if ConflictRetry.shouldRetry(outcome, hadAttachToPersonId: hadAttachToPersonId) {
                // Exactly one resubmit -- whatever this answers is final,
                // even a second "conflict". No retry loop.
                outcome = try await resend()
            }
            if outcome.status == "conflict" {
                // Nothing was written on this branch, whether that is the
                // original answer (no attach guess to strip and retry with)
                // or the resubmit's own answer (retried once, still no).
                // The one copy of what was written is this queue item, so
                // it is kept -- the same retained-for-retry treatment a
                // network failure gets below -- not sent. A later pass
                // retries this same capture again, which will replay this
                // exact conflict until something about it actually changes
                // -- Z1: that replay must not notify a second time, so the
                // person learns once, not on every future launch.
                result.kept += 1
                if !conflictMarks.hasNotified(captureId) {
                    conflictMarks.markNotified(captureId)
                    result.notices.append(
                        HandleDropState.Event(
                            personId: outcome.personId, personName: displayName, platform: platform,
                            reason: .conflict
                        )
                    )
                }
                return
            }
            // Resolved to something other than a conflict -- whatever mark
            // this capture carried from an earlier pass no longer describes
            // it. Before `remove()`: if removal somehow fails (it is
            // `try?`), the capture stays queued, and the mark should already
            // be gone so the next pass can notify about a genuinely new
            // problem rather than staying silently suppressed forever.
            conflictMarks.clear(captureId)
            if outcome.noteTruncated { result.truncatedNotes += 1 }
            if outcome.handleDropped {
                Self.logHandleDropped(platform: platform)
                result.notices.append(
                    HandleDropState.Event(
                        personId: outcome.personId, personName: displayName, platform: platform, reason: .handleFull
                    )
                )
            }
            remove()
            result.sent += 1
        } catch {
            // Kept, not dropped: the usual reason is that there was no
            // network, and losing the capture is the one outcome the whole
            // queue exists to prevent.
            result.kept += 1
        }
    }

    private func bounded<Value>(_ call: @escaping () async throws -> Value) async throws -> Value {
        let work = Task { try await call() }
        guard let value = await work.value(within: .seconds(deadline)) else {
            throw DrainError.timedOut
        }
        return value
    }

    private static func logHandleDropped(platform: String) {
        logger.notice("handle dropped at the 8-handle cap: \(platform, privacy: .public)")
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
