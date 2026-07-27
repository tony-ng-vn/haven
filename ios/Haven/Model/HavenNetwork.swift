import Combine
import ConvexMobile
import Foundation

/// How long Haven waits on the network before it says so.
///
/// One number, because four screens waiting four different lengths would be a
/// difference someone can feel and nobody chose. Long enough for a slow
/// connection, short enough that a dead one does not hold a screen.
enum HavenNetwork {
    static let deadline: TimeInterval = 12

    /// Subscribes to a Convex query and gives up if nothing arrives in time.
    ///
    /// The bound is the whole point. The Convex client reconnects rather than
    /// failing, so a read with no network does not error, it waits, and nothing
    /// else would ever end that wait. A screen that opens on a spinner forever
    /// is the one outcome with no way out of it, so every read here can end in
    /// "we never heard back" and offer to try again.
    ///
    /// - Parameters:
    ///   - firstValueOnly: ends the stream after one value. Onboarding wants
    ///     this: while it runs, the device is the sole writer and every commit
    ///     hands back the new card, so a live subscription would only add a
    ///     second, later source that can move someone off the question they are
    ///     in the middle of answering. Everywhere else, an edit made on another
    ///     device should land.
    ///   - onSilence: called when the stream ends without ever producing a
    ///     value. Any ending counts, not just a failure: a timeout finishes the
    ///     stream quietly, and that is what "we never heard back" looks like.
    @MainActor
    static func subscribe<Value: Decodable>(
        to name: String,
        with args: [String: ConvexEncodable?] = [:],
        yielding: Value.Type,
        firstValueOnly: Bool = false,
        onValue: @escaping (Value) -> Void,
        onSilence: @escaping () -> Void
    ) -> AnyCancellable {
        let stream = convex.subscribe(to: name, with: args, yielding: Value.self)
        let bounded = firstValueOnly
            ? stream.first().eraseToAnyPublisher()
            : stream.eraseToAnyPublisher()
        return bounded
            .timeout(.seconds(deadline), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { _ in onSilence() } receiveValue: { onValue($0) }
    }
}
