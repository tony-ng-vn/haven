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
    ///
    /// Deliberately not a `withTaskGroup` racing `self.value` against a sleep.
    /// A task group cannot return before every task added to it has finished,
    /// and a child doing `await self.value` only finishes once `self` itself
    /// does -- cancelling that child does not reach `self`, and `Task.value`
    /// does not check the awaiting side's own cancellation either. So a group
    /// built that way never actually returns early for a task that genuinely
    /// never completes; it only looks like it does, because every task this
    /// method has ever been tried against in practice finished soon enough
    /// that nobody noticed the group was still waiting on it underneath.
    ///
    /// Two unstructured tasks race to resume one continuation instead, and
    /// whichever loses is abandoned rather than joined -- which is what
    /// actually delivers "bounds the wait, not the work": the slow side is
    /// left running with nothing left listening to it, and this function
    /// returns the moment the other side answers.
    func value(within deadline: Duration) async -> Success? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Success?, Never>) in
            let once = ResumeOnce(continuation)
            // Spelled out, because inside an extension on `Task` a bare
            // `Task { }` means `Self.init`, which would force these two
            // fire-and-forget tasks into `Task<Success, Failure>` instead of
            // their own `Void` result.
            Task<Void, Never> {
                let value = try? await self.value
                await once.resume(with: value)
            }
            Task<Void, Never> {
                try? await Task<Never, Never>.sleep(for: deadline)
                await once.resume(with: nil)
            }
        }
    }
}

/// Resumes a continuation exactly once, whichever of two racing tasks gets
/// there first.
///
/// `CheckedContinuation` traps on a second resume, so the loser has to find
/// out it lost rather than call it -- that is this actor's whole job. Actor
/// isolation serializes the two racing calls into `resume(with:)`, which is
/// what makes "exactly once" true without a lock: the continuation is taken
/// and cleared in the same isolated step, so whichever call arrives second
/// finds nothing left to resume.
private actor ResumeOnce<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    func resume(with value: Value?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}
