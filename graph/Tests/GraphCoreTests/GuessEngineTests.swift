import XCTest
@testable import GraphCore

/// A scripted, in-memory provider: records every prompt it was asked to guess on (so tests
/// can assert what GuessEngine actually sent it) and returns pre-scripted results in order.
/// @unchecked Sendable: guarded entirely by `lock`, a plain NSLock, since GuessEngine may call
/// this from a detached task in real use even though these tests call it from one Task at a time.
private final class ScriptedProvider: NameGuessProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var promptsSeenStorage: [String] = []
    private let scriptedResults: [Result<NameGuess, Error>]
    private var nextIndex = 0
    /// Optional artificial delay per call, so a cancellation test has a window to cancel
    /// while a call is in flight.
    private let delayNanoseconds: UInt64

    init(scriptedResults: [Result<NameGuess, Error>], delayNanoseconds: UInt64 = 0) {
        self.scriptedResults = scriptedResults
        self.delayNanoseconds = delayNanoseconds
    }

    var promptsSeen: [String] {
        lock.lock(); defer { lock.unlock() }
        return promptsSeenStorage
    }

    func guess(prompt: String) async throws -> NameGuess {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        // withLock, not lock()/unlock() directly: NSLock's plain lock/unlock calls are
        // unavailable from an async function body (Swift's async-safe-locking rule), even
        // though the actual critical section here is synchronous either way.
        let index = lock.withLock {
            let currentIndex = nextIndex
            promptsSeenStorage.append(prompt)
            nextIndex += 1
            return currentIndex
        }

        guard index < scriptedResults.count else { throw NameGuessError.badResponse }
        switch scriptedResults[index] {
        case .success(let guess): return guess
        case .failure(let error): throw error
        }
    }
}

/// Collects onGuess/completion/onOutcome callback data from a GuessEngine.run call. A plain
/// lock-guarded class, not a var captured directly in the test: these closures are typed
/// @Sendable, so the compiler requires whatever they mutate to be provably safe across
/// concurrency domains, even though this stub implementation happens to call them synchronously
/// and in order.
private final class ResultCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var deliveredKeysStorage: [String] = []
    private var guessesByKeyStorage: [String: NameGuess] = [:]
    private var outcomeStorage: GuessEngineOutcome?
    private var candidateOutcomesStorage: [GuessOutcome] = []

    var deliveredKeys: [String] {
        lock.lock(); defer { lock.unlock() }
        return deliveredKeysStorage
    }
    var guessesByKey: [String: NameGuess] {
        lock.lock(); defer { lock.unlock() }
        return guessesByKeyStorage
    }
    var outcome: GuessEngineOutcome? {
        lock.lock(); defer { lock.unlock() }
        return outcomeStorage
    }
    var candidateOutcomes: [GuessOutcome] {
        lock.lock(); defer { lock.unlock() }
        return candidateOutcomesStorage
    }

    func recordGuess(_ key: String, _ guess: NameGuess) {
        lock.lock()
        deliveredKeysStorage.append(key)
        guessesByKeyStorage[key] = guess
        lock.unlock()
    }

    func recordOutcome(_ outcome: GuessEngineOutcome) {
        lock.lock(); outcomeStorage = outcome; lock.unlock()
    }

    func recordCandidateOutcome(_ outcome: GuessOutcome) {
        lock.lock(); candidateOutcomesStorage.append(outcome); lock.unlock()
    }
}

/// A snippet whose text actually grounds `name` (self-introduction phrasing), so tests focused
/// on orchestration (ordering, cancellation, error handling) don't accidentally exercise the
/// grounding-rejection path they aren't testing. A free function, not an instance method: it
/// must be callable from inside a @Sendable closure without capturing `self`
/// (XCTestCase is not Sendable), same reasoning as `candidate(_:)` below.
private func groundedSnippet(for name: String) -> Snippet {
    Snippet(text: "hi its \(name) checking in", isFromMe: false)
}

final class GuessEngineTests: XCTestCase {

    private func candidate(_ key: String) -> GuessCandidate {
        GuessCandidate(key: key, context: .person(identifier: key))
    }

    func testCachedKeysAreSkipped() async {
        let provider = ScriptedProvider(scriptedResults: [.success(NameGuess(name: "Priya Ashcombe"))])
        let collector = ResultCollector()

        await GuessEngine.run(
            candidates: [candidate("cached-key"), candidate("new-key")],
            cache: ["cached-key": NameGuess(name: "Already Known")],
            snippetSource: { key in key == "new-key" ? [groundedSnippet(for: "Priya Ashcombe")] : [] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { collector.recordOutcome($0) }
        )

        XCTAssertEqual(provider.promptsSeen.count, 1, "the cached key must never reach the provider")
        XCTAssertEqual(collector.deliveredKeys, ["new-key"])
    }

    func testResultsAreDeliveredViaOnGuessInOrder() async {
        let names = ["Ravi Solano", "Priya Ashcombe", "Deshawn Marlowe"]
        let provider = ScriptedProvider(scriptedResults: names.map { .success(NameGuess(name: $0)) })
        let collector = ResultCollector()
        let snippetsByKey = ["a": names[0], "b": names[1], "c": names[2]]

        await GuessEngine.run(
            candidates: [candidate("a"), candidate("b"), candidate("c")],
            cache: [:],
            snippetSource: { key in [groundedSnippet(for: snippetsByKey[key]!)] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { collector.recordOutcome($0) }
        )

        XCTAssertEqual(collector.deliveredKeys, ["a", "b", "c"])
    }

    func testProviderUnreachableStopsThePassImmediately() async {
        let provider = ScriptedProvider(scriptedResults: [
            .failure(NameGuessError.providerUnreachable),
            .success(NameGuess(name: "Never Reached")),
            .success(NameGuess(name: "Also Never Reached")),
        ])
        let collector = ResultCollector()

        await GuessEngine.run(
            candidates: [candidate("a"), candidate("b"), candidate("c")],
            cache: [:],
            // Non-empty so the no-evidence short circuit doesn't mask what this test is
            // actually checking (that a provider failure, not a lack of evidence, is why the
            // pass stops after the first candidate).
            snippetSource: { _ in [Snippet(text: "just checking in about plans", isFromMe: false)] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { collector.recordOutcome($0) }
        )

        XCTAssertTrue(collector.deliveredKeys.isEmpty, "no guess should be delivered once the provider is unreachable")
        XCTAssertEqual(provider.promptsSeen.count, 1, "the pass must stop after the first failure, not try the rest")
        XCTAssertEqual(collector.outcome, .stoppedProviderUnreachable)
    }

    func testBadResponseSkipsOneTargetAndContinues() async {
        let provider = ScriptedProvider(scriptedResults: [
            .success(NameGuess(name: "Ravi Solano")),
            .failure(NameGuessError.badResponse),
            .success(NameGuess(name: "Deshawn Marlowe")),
        ])
        let collector = ResultCollector()
        let snippetsByKey = ["a": "Ravi Solano", "b": "irrelevant", "c": "Deshawn Marlowe"]

        await GuessEngine.run(
            candidates: [candidate("a"), candidate("b"), candidate("c")],
            cache: [:],
            snippetSource: { key in [groundedSnippet(for: snippetsByKey[key]!)] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { collector.recordOutcome($0) }
        )

        XCTAssertEqual(collector.deliveredKeys, ["a", "c"], "the badResponse target must be skipped, everything else continues")
        XCTAssertEqual(collector.outcome, .completed)
    }

    func testCancellationStopsPromptly() async {
        // A real delay per call so the outer task has a genuine window to cancel while the
        // first call is still in flight, rather than racing against work that finishes instantly.
        let names = ["Ravi Solano", "Priya Ashcombe", "Deshawn Marlowe", "Junko Whitfield", "Tomas Eldridge"]
        let provider = ScriptedProvider(
            scriptedResults: names.map { .success(NameGuess(name: $0)) },
            delayNanoseconds: 100_000_000
        )
        let collector = ResultCollector()
        // Built outside the Task closure below: `candidate(_:)` is an instance method, and
        // capturing it (or self) inside a @Sendable-checked closure is what the compiler
        // objects to, not the plain [GuessCandidate] value this produces.
        let candidates = (0..<5).map { candidate("k\($0)") }
        // A single catch-all snippet naming everyone: this test is about cancellation timing,
        // not grounding, so every candidate gets evidence for whichever name it is scripted to
        // receive without needing a per-key lookup table.
        let rosterSnippet = Snippet(text: names.joined(separator: " "), isFromMe: false)

        let task = Task {
            await GuessEngine.run(
                candidates: candidates,
                cache: [:],
                snippetSource: { _ in [rosterSnippet] },
                provider: provider,
                onGuess: { key, guess in collector.recordGuess(key, guess) },
                completion: { collector.recordOutcome($0) }
            )
        }
        try? await Task.sleep(nanoseconds: 20_000_000) // well inside the first call's delay
        task.cancel()
        await task.value

        XCTAssertLessThan(collector.deliveredKeys.count, 5, "cancellation must stop the pass before all candidates are processed")
        XCTAssertEqual(collector.outcome, .cancelled)
    }

    /// A cancellation that lands while awaiting the LAST candidate's provider call is caught by
    /// the generic `catch` (CancellationError has no special case there), so the loop exits
    /// normally on its own -- the completion must still report .cancelled, not .completed, or a
    /// caller (AppModel) would treat a cancelled pass as finished and clobber the next pass's
    /// in-progress state.
    func testCancellationDuringTheFinalCandidateStillReportsCancelled() async {
        let names = ["Ravi Solano", "Priya Ashcombe", "Deshawn Marlowe", "Junko Whitfield", "Tomas Eldridge"]
        let provider = ScriptedProvider(
            scriptedResults: names.map { .success(NameGuess(name: $0)) },
            delayNanoseconds: 100_000_000
        )
        let collector = ResultCollector()
        let candidates = (0..<5).map { candidate("k\($0)") }
        let rosterSnippet = Snippet(text: names.joined(separator: " "), isFromMe: false)

        let task = Task {
            await GuessEngine.run(
                candidates: candidates,
                cache: [:],
                snippetSource: { _ in [rosterSnippet] },
                provider: provider,
                onGuess: { key, guess in collector.recordGuess(key, guess) },
                completion: { collector.recordOutcome($0) }
            )
        }
        // Inside the 5th (last) call's 100ms delay window, not the first's.
        try? await Task.sleep(nanoseconds: 450_000_000)
        task.cancel()
        await task.value

        XCTAssertEqual(collector.outcome, .cancelled, "cancelling during the last candidate must not be reported as completed")
    }

    // MARK: - No evidence, no prompt (item 2 of the brief)

    func testCandidateWithNoSnippetsNeverReachesTheProvider() async {
        let provider = ScriptedProvider(scriptedResults: [.success(NameGuess(name: "Should Never Be Used"))])
        let collector = ResultCollector()

        await GuessEngine.run(
            candidates: [candidate("no-evidence-key")],
            cache: [:],
            snippetSource: { _ in [] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { collector.recordOutcome($0) },
            onOutcome: { collector.recordCandidateOutcome($0) }
        )

        XCTAssertEqual(provider.promptsSeen.count, 0, "a candidate with zero snippets must never be sent to the model")
        XCTAssertTrue(collector.deliveredKeys.isEmpty)
        XCTAssertEqual(collector.candidateOutcomes, [.noEvidence])
        XCTAssertEqual(collector.outcome, .completed)
    }

    func testNoEvidenceCandidateDoesNotStopThePassForLaterCandidates() async {
        let provider = ScriptedProvider(scriptedResults: [.success(NameGuess(name: "Ravi Solano"))])
        let collector = ResultCollector()

        await GuessEngine.run(
            candidates: [candidate("no-evidence-key"), candidate("has-evidence-key")],
            cache: [:],
            snippetSource: { key in key == "has-evidence-key" ? [groundedSnippet(for: "Ravi Solano")] : [] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { collector.recordOutcome($0) }
        )

        XCTAssertEqual(provider.promptsSeen.count, 1)
        XCTAssertEqual(collector.deliveredKeys, ["has-evidence-key"])
    }

    // MARK: - Grounding rejection (item 3 of the brief)

    func testUngroundedGuessIsNotDeliveredButThePassContinues() async {
        let provider = ScriptedProvider(scriptedResults: [
            .success(NameGuess(name: "Emily Wilson")), // hallucinated: not in the snippet below
            .success(NameGuess(name: "Ravi Solano")),
        ])
        let collector = ResultCollector()
        let snippetsByKey = [
            "hallucinated-key": "ok see you then, sounds good",
            "grounded-key": "hi its Ravi Solano checking in",
        ]

        await GuessEngine.run(
            candidates: [candidate("hallucinated-key"), candidate("grounded-key")],
            cache: [:],
            snippetSource: { key in [Snippet(text: snippetsByKey[key]!, isFromMe: false)] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { collector.recordOutcome($0) },
            onOutcome: { collector.recordCandidateOutcome($0) }
        )

        XCTAssertEqual(provider.promptsSeen.count, 2, "the provider is still asked -- grounding is checked on its answer, not used to skip the call")
        XCTAssertEqual(collector.deliveredKeys, ["grounded-key"], "the ungrounded guess must never be delivered")
        XCTAssertEqual(collector.candidateOutcomes, [.rejectedUngrounded, .accepted])
        XCTAssertEqual(collector.outcome, .completed, "an ungrounded guess is discarded, not treated as a pass-stopping error")
    }

    // MARK: - Model decline (item 1 of the brief)

    func testDeclinedByModelIsNotDeliveredAndDoesNotStopThePass() async {
        let provider = ScriptedProvider(scriptedResults: [
            .failure(NameGuessError.declined),
            .success(NameGuess(name: "Ravi Solano")),
        ])
        let collector = ResultCollector()

        await GuessEngine.run(
            candidates: [candidate("declined-key"), candidate("accepted-key")],
            cache: [:],
            snippetSource: { _ in [groundedSnippet(for: "Ravi Solano")] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { collector.recordOutcome($0) },
            onOutcome: { collector.recordCandidateOutcome($0) }
        )

        XCTAssertEqual(collector.deliveredKeys, ["accepted-key"], "a decline must not be cached as a name")
        XCTAssertEqual(collector.candidateOutcomes, [.declinedByModel, .accepted])
        XCTAssertEqual(collector.outcome, .completed, "a decline is an answer, not an error -- it must not stop the pass")
    }

    // THE PRIVACY TEST, non-negotiable per the brief. Every assertion message below is static
    // -- never interpolating the sentinel or the prompt -- so a failure report itself cannot
    // become the leak this test exists to rule out.
    func testMessageTextNeverReachesTheSavedOverridesStore() async throws {
        let sentinel = "SENTINEL-PRIVACY-7f2ac9-never-persist"
        let candidateKey = "+14155559999"
        let expectedGuessName = "Jordan Rivera"

        let provider = ScriptedProvider(scriptedResults: [.success(NameGuess(name: expectedGuessName, detail: "A guess"))])
        let collector = ResultCollector()

        await GuessEngine.run(
            candidates: [GuessCandidate(key: candidateKey, context: .person(identifier: candidateKey))],
            cache: [:],
            // Grounds the guess (so it survives the grounding check and reaches onGuess) while
            // still carrying the sentinel, so the positive control below stays meaningful.
            snippetSource: { _ in [Snippet(text: "hi its \(expectedGuessName). \(sentinel)", isFromMe: false)] },
            provider: provider,
            onGuess: { key, guess in collector.recordGuess(key, guess) },
            completion: { _ in }
        )

        // Positive control: the sentinel really did flow into the prompt the provider saw --
        // otherwise the "sentinel appears nowhere in the saved file" assertion below would be
        // vacuously true regardless of whether this pass leaks anything at all.
        let promptContainedSentinel = provider.promptsSeen.contains { $0.contains(sentinel) }
        XCTAssertTrue(promptContainedSentinel, "positive control failed: the sentinel never reached the provider, so the rest of this test proves nothing")

        var overrides = Overrides()
        overrides.nameGuesses = collector.guessesByKey

        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuessEngineTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeFileURL = storeDirectory.appendingPathComponent("overrides.json")
        try OverridesStore(fileURL: storeFileURL).save(overrides)

        let rawBytes = try Data(contentsOf: storeFileURL)
        let rawText = try XCTUnwrap(String(data: rawBytes, encoding: .utf8))

        XCTAssertFalse(rawText.contains(sentinel), "message text must never appear in the saved overrides file")
        XCTAssertTrue(rawText.contains(expectedGuessName), "only the derived guess name should persist")
    }
}
