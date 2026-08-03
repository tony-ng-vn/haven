import Foundation

/// A local-first or (in principle, later) cloud model backend that turns a built prompt into
/// a NameGuess. GuessEngine talks only to this protocol, never to a concrete provider, so it
/// can be driven entirely by a scripted mock in tests.
public protocol NameGuessProvider: Sendable {
    func guess(prompt: String) async throws -> NameGuess
}

/// The three outcomes GuessEngine needs to tell apart: an unreachable provider stops the whole
/// pass (no point hammering a dead server); a bad response for one target is just skipped, one
/// guess lost, everything else continues; and a decline is not a failure at all -- the model
/// explicitly said it does not have enough evidence, which is the correct answer, not an error.
/// GuessEngine treats `.declined` the same way it treats `.badResponse` (skip this target, keep
/// going) but the cases stay distinct so a caller that wants to count "the model didn't know"
/// separately from "the response was unusable" can.
public enum NameGuessError: Error, Sendable, Equatable {
    case providerUnreachable
    case badResponse
    case declined
}
