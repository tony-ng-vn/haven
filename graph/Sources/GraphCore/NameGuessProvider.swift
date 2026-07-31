import Foundation

/// A local-first or (in principle, later) cloud model backend that turns a built prompt into
/// a NameGuess. GuessEngine talks only to this protocol, never to a concrete provider, so it
/// can be driven entirely by a scripted mock in tests.
public protocol NameGuessProvider: Sendable {
    func guess(prompt: String) async throws -> NameGuess
}

/// The only two failure shapes GuessEngine needs to tell apart: an unreachable provider stops
/// the whole pass (no point hammering a dead server), while a bad response for one target is
/// just skipped, one guess lost, everything else continues.
public enum NameGuessError: Error, Sendable, Equatable {
    case providerUnreachable
    case badResponse
}
