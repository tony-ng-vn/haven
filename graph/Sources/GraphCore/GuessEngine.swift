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

/// What happened to ONE candidate during a pass -- optional telemetry for a caller (graph-cli's
/// `guess` subcommand) that wants to report where the unnamed handles actually went, beyond
/// just "was a name delivered or not". Never carries a name or any snippet text: these are the
/// distinctions the brief asks to count (abstained vs. rejected by grounding vs. never even
/// asked), not a second channel for the guess itself.
public enum GuessOutcome: Sendable, Equatable {
    /// The guess passed the grounding check and was delivered via `onGuess`.
    case accepted
    /// The model explicitly declined (NameGuessError.declined) -- a correct answer, not a failure.
    case declinedByModel
    /// The model returned a name, but it is not supported by the snippets it was shown; discarded
    /// as if the model had abstained.
    case rejectedUngrounded
    /// Person candidates only: the guessed name IS grounded in the snippets shown, but only in a
    /// message someone other than the candidate sent -- the user addressing or discussing them,
    /// or (for the words to be there at all) a third party. That is not evidence the candidate
    /// carries that name themselves. Kept distinct from `.rejectedUngrounded` because the words
    /// really are present; only the speaker is wrong (see GuessAttribution's doc comment for the
    /// measured mechanism this guards against).
    case rejectedScoped
    /// Zero snippets were available for this candidate, so the model was never asked at all.
    case noEvidence
    /// badResponse or any other unparseable/unexpected provider failure for this one candidate.
    case providerError
}

/// Cache repair for a guess cache poisoned by the old no-abstention prompt: drops every stored
/// name guess while leaving every other piece of the owner's curation (hidden/removed
/// identifiers, merge answers, acquaintance roster markers) untouched. A pure function, not
/// something inlined at the CLI call site, so "does this touch anything it shouldn't" is
/// answered by a unit test on the returned value rather than by re-reading the CLI code.
/// Backs graph-cli's `guess --reguess` flag: the caller saves the returned Overrides back
/// through the same OverridesStore the app uses, which makes every previously-guessed
/// candidate pending again for the next pass.
public enum GuessCacheRepair {
    public static func purgingNameGuesses(from overrides: Overrides) -> (result: Overrides, droppedCount: Int) {
        var result = overrides
        let droppedCount = result.nameGuesses.count
        result.nameGuesses = [:]
        return (result, droppedCount)
    }
}

/// Orchestrates one full model-pass run: serial (a local model has no concurrency to exploit
/// and hammering it wouldn't help), resync-cheap (skips anything already in the cache), and
/// cancelable. Pure orchestration -- no I/O of its own: SnippetReader access and the actual
/// network call are both pushed out to the caller-supplied closure/provider, which is what
/// makes this fully testable with a scripted mock and no real database or network.
public enum GuessEngine {
    /// `onOutcome` is appended last with a default of nil so existing call sites (AppModel's
    /// own pass) keep compiling unchanged -- it is optional per-candidate telemetry for a
    /// caller that wants a breakdown beyond "was a name delivered", not part of the core
    /// contract every caller must handle.
    public static func run(
        candidates: [GuessCandidate],
        cache: [String: NameGuess],
        snippetSource: @Sendable (String) -> [Snippet],
        provider: NameGuessProvider,
        onGuess: @Sendable (String, NameGuess) -> Void,
        completion: @Sendable (GuessEngineOutcome) -> Void,
        onOutcome: (@Sendable (GuessOutcome) -> Void)? = nil
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

            // No evidence, no prompt: asking the model to name someone from nothing is what
            // guaranteed fabrication before this fix. Short-circuit here, before GuessPrompt is
            // even built, rather than relying on the model to decline on an empty prompt.
            guard !snippets.isEmpty else {
                onOutcome?(.noEvidence)
                continue
            }

            let prompt = GuessPrompt.build(snippets: snippets, context: candidate.context)

            do {
                let guess = try await provider.guess(prompt: prompt)
                // Scoping: for a PERSON candidate, only a message THEY sent is evidence they
                // carry that name -- one the user sent could be addressing them, but could just
                // as easily be discussing a third party, and either way it says nothing about
                // who this candidate actually is. A group has no analogous "self" (its name is
                // legitimately informed by whatever anyone in it, including the user, said), so
                // group candidates are ungrounded against every snippet they were shown, as
                // before. The prompt itself (built above) still shows the model the full
                // exchange either way -- only what counts as PROOF is restricted here.
                let evidenceSnippets: [Snippet]
                if case .person = candidate.context {
                    evidenceSnippets = snippets.filter { !$0.isFromMe }
                } else {
                    evidenceSnippets = snippets
                }

                // The grounding check, not the model's own confidence, decides acceptance:
                // every significant token of the guessed name must actually appear in the
                // evidence snippets. A guess that fails this is discarded exactly as if the
                // model had abstained -- this is the load-bearing fix for the hallucination bug,
                // deliberately model-independent. Unchanged, and not weakened: this is the same
                // #206 check, only handed a narrower (for persons) input.
                guard GuessGrounding.isGrounded(name: guess.name, snippets: evidenceSnippets) else {
                    // Distinguishing an outright hallucination from a real-but-misattributed
                    // mention costs one extra (cheap, in-memory, no network) grounding check,
                    // only on this already-rejecting path -- never on the common accepted path.
                    let wouldGroundOnFullSnippets = evidenceSnippets.count != snippets.count
                        && GuessGrounding.isGrounded(name: guess.name, snippets: snippets)
                    onOutcome?(wouldGroundOnFullSnippets ? .rejectedScoped : .rejectedUngrounded)
                    continue
                }
                onGuess(candidate.key, guess)
                onOutcome?(.accepted)
            } catch NameGuessError.providerUnreachable {
                // No point hammering a dead server: stop the whole pass here, not just this one target.
                completion(.stoppedProviderUnreachable)
                return
            } catch NameGuessError.declined {
                // Not an error: the model explicitly said it does not know. The handle simply
                // stays unnamed and remains eligible for a future pass.
                onOutcome?(.declinedByModel)
                continue
            } catch {
                // badResponse, or anything else unparseable: skip this one target, keep going.
                onOutcome?(.providerError)
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
