import Foundation

/// One thing to guess a name for. `key` is what the cache and the caller's snippet-source
/// closure are both keyed on: a person candidate uses their normalized identifier directly,
/// a group candidate uses "group:<guid>" (deliberately NOT the same "chat:<guid>" prefix a
/// group's own graph node id uses -- see NodeLabel, which bridges the two).
public struct GuessCandidate: Sendable, Equatable {
    public let key: String
    public let context: GuessContext

    public init(key: String, context: GuessContext) {
        self.key = key
        self.context = context
    }
}

/// How one full pass ended.
public enum GuessEngineOutcome: Sendable, Equatable {
    case completed
    case stoppedProviderUnreachable
    case cancelled
}

/// Orchestrates one full model-pass run: serial (a local model has no concurrency to exploit
/// and hammering it wouldn't help), resync-cheap (skips anything already in the cache), and
/// cancelable. Pure orchestration -- no I/O of its own: SnippetReader access and the actual
/// network call are both pushed out to the caller-supplied closure/provider, which is what
/// makes this fully testable with a scripted mock and no real database or network.
public enum GuessEngine {
    public static func run(
        candidates: [GuessCandidate],
        cache: [String: NameGuess],
        snippetSource: @Sendable (String) -> [Snippet],
        provider: NameGuessProvider,
        onGuess: @Sendable (String, NameGuess) -> Void,
        completion: @Sendable (GuessEngineOutcome) -> Void
    ) async {
        for candidate in candidates {
            if Task.isCancelled {
                completion(.cancelled)
                return
            }
            guard cache[candidate.key] == nil else { continue }

            // Snippets are read lazily, one candidate at a time, right before the prompt that
            // consumes them: nothing here holds message text any longer than one iteration.
            let snippets = snippetSource(candidate.key)
            let prompt = GuessPrompt.build(snippets: snippets, context: candidate.context)

            do {
                let guess = try await provider.guess(prompt: prompt)
                onGuess(candidate.key, guess)
            } catch NameGuessError.providerUnreachable {
                // No point hammering a dead server: stop the whole pass here, not just this one target.
                completion(.stoppedProviderUnreachable)
                return
            } catch {
                // badResponse, or anything else unparseable: skip this one target, keep going.
                continue
            }
        }
        // A cancellation that lands while awaiting the LAST candidate's provider call is caught
        // above by the generic `catch` (CancellationError has no special case there) and the
        // loop exits normally -- so this cannot simply be `.completed`. Re-checking here is what
        // stops a cancelled pass from being reported as finished.
        completion(Task.isCancelled ? .cancelled : .completed)
    }
}
