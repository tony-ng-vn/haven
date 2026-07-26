import Foundation

// `Task` already requires `Success: Sendable`, so this needs no constraint of
// its own beyond a throwing task.
extension Task where Failure == Error {
    /// The task's value, or nil if it did not arrive in time or threw.
    ///
    /// Bounds the wait, not the work. The Convex client does not check
    /// cancellation part way through a call, so the call carries on after this
    /// returns; what matters is that the person stops waiting on it and gets
    /// their controls back. A late success is harmless here, because every
    /// onboarding write sends the same values again.
    func value(within deadline: Duration) async -> Success? {
        await withTaskGroup(of: Success?.self) { group in
            group.addTask { try? await self.value }
            group.addTask {
                try? await Task.sleep(for: deadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
