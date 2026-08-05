import Testing
@testable import Haven

// The bound every write in the app leans on: MyCardModel, PersonModel,
// OnboardingModel, ConnectModel and AskModel all wrap a Convex call in
// Task.value(within:) rather than awaiting it directly, on the belief that a
// dead connection gives control back at the deadline instead of never. This
// is where that belief is checked against a task that actually never
// completes, not just one that is merely slow.

@Suite("Task deadline")
struct TaskDeadlineTests {
    /// The one case the whole mechanism exists for. Wrapped in
    /// `withTestTimeout` on purpose: that helper does not share a shape with
    /// `value(within:)`, so this test fails on its own bounded timeout rather
    /// than hanging the suite if `value(within:)` regresses back to waiting
    /// on the task itself.
    @Test("a task that never completes still returns nil, in bounded time")
    func neverCompletingTaskReturnsNil() async throws {
        let never = Task<Int, Error> {
            try await withCheckedThrowingContinuation { (_: CheckedContinuation<Int, Error>) in
                // Never resumed. Nothing here ever checks cancellation either,
                // which is what a Convex call on a dead connection looks like
                // from this side.
            }
        }

        let start = ContinuousClock.now
        let result = try await withTestTimeout {
            await never.value(within: .milliseconds(200))
        }
        let elapsed = ContinuousClock.now - start

        #expect(result == nil)
        // Generous above the 200ms deadline for scheduling jitter, and far
        // below the 2s safety net, so a bound that quietly stopped working
        // and fell back to the safety net would still fail this specific
        // assertion rather than reading as a slow pass.
        #expect(elapsed < .seconds(1), "\(elapsed)")
    }

    @Test("a task that finishes well inside the deadline returns its value")
    func fastTaskReturnsItsValue() async throws {
        let fast = Task<Int, Error> {
            try await Task.sleep(for: .milliseconds(20))
            return 42
        }

        let result = await fast.value(within: .milliseconds(500))

        #expect(result == 42)
    }

    /// The deadline is on the wait, not the work: a task that finishes after
    /// it still answers nil, and promptly -- not after however long the task
    /// itself took.
    @Test("a task that finishes after the deadline returns nil, not its value")
    func lateTaskReturnsNil() async throws {
        let slow = Task<Int, Error> {
            try await Task.sleep(for: .milliseconds(500))
            return 7
        }

        let start = ContinuousClock.now
        let result = await slow.value(within: .milliseconds(100))
        let elapsed = ContinuousClock.now - start

        #expect(result == nil)
        // Well short of the 500ms the task itself takes: this is the
        // difference between bounding the wait and merely computing, late,
        // what the answer would have been.
        #expect(elapsed < .milliseconds(400), "\(elapsed)")
    }
}
