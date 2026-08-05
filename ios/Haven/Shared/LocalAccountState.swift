import Foundation

/// Everything on this device that belongs to whichever account is signed in,
/// but is not keyed by their user id the way `WidgetPromoDismissal` and
/// `OnboardingSkips` are.
///
/// `DirectoryMirrorStore` and `CaptureQueue` both exist for the share
/// extension, which has no notion of "signed in" at all -- there is one
/// mirror file and one set of queue files per device, full stop. Left alone
/// across a sign-out, the next account on this phone would open the add
/// sheet and see the previous account's people offered back as "already
/// saved as...", and any capture still queued when the first account signed
/// out would drain into whichever account signs in next, filed under a name
/// it was never about.
enum LocalAccountState {
    /// Clears the mirror and every capture still waiting to send, image
    /// files included.
    ///
    /// This is a deliberate loss, not a side effect swallowed for
    /// convenience: an unsent capture belongs to the account that made it,
    /// and there is no way after a sign-out to say which account that was,
    /// so keeping it around risks filing it under the wrong person, which is
    /// worse than not filing it at all.
    ///
    /// Best-effort throughout: a file that is already gone, or a container
    /// the App Group was never provisioned for, is not a failure here --
    /// there is nothing left to clear either way, which is the same reading
    /// `CaptureDrain` already gives a capture it cannot find on disk.
    static func clear(
        mirror: DirectoryMirrorStore = .forApp(),
        queues: [CaptureQueue] = CaptureQueue.drainable()
    ) {
        try? mirror.clear()
        for queue in queues {
            for capture in queue.pending() {
                try? queue.remove(capture)
            }
        }
    }
}
