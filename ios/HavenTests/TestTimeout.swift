import Foundation

// Shared by any test that has to prove something finishes in bounded time
// without trusting the mechanism under test to be the thing that bounds it --
// CaptureDrainTests and TaskDeadlineTests both stand something up that might,
// on a regression, never return at all.

/// Fails a test rather than hanging the runner if `work` does not finish
/// within `seconds`.
///
/// Deliberately not `Task.value(within:)`, even though that is the very
/// function `TaskDeadlineTests` exists to check: a `withTaskGroup` cannot
/// return before every task it started has finished, so a safety net built
/// on the same shape could hang on exactly the regression it is meant to
/// catch. `work` here runs unstructured and is never joined by the losing
/// path, so a `work` that never finishes leaks harmlessly instead of wedging
/// this function.
func withTestTimeout<T: Sendable>(
    seconds: Double = 2,
    _ work: @escaping @Sendable () async -> T
) async throws -> T {
    let box = TestResultBox<T>()
    Task {
        let value = await work()
        await box.set(value)
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    while ContinuousClock.now < deadline {
        if let value = await box.get() { return value }
        try? await Task.sleep(for: .milliseconds(5))
    }
    throw TestTimedOut()
}

struct TestTimedOut: Error, CustomStringConvertible {
    var description: String { "did not return within the test's own safety timeout" }
}

private actor TestResultBox<T: Sendable> {
    private var value: T?
    func set(_ newValue: T) { value = newValue }
    func get() -> T? { value }
}
