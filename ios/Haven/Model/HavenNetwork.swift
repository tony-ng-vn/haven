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
    ///     value -- for a `firstValueOnly` read, a timeout finishes the stream
    ///     quietly, and that is what "we never heard back" looks like. For a
    ///     live subscription, the deadline only guards that first answer; once
    ///     one has arrived, `onSilence` is reserved for the underlying
    ///     subscription actually ending (the client gave up reconnecting), not
    ///     for an ordinary quiet stretch between real changes. See the
    ///     live-subscription branch below for why that distinction is load
    ///     bearing rather than cosmetic.
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

        if firstValueOnly {
            return stream.first()
                .timeout(.seconds(deadline), scheduler: DispatchQueue.main)
                .receive(on: DispatchQueue.main)
                .sink { _ in onSilence() } receiveValue: { onValue($0) }
        }

        return LiveSubscription.attach(
            to: stream,
            deadline: deadline,
            onValue: onValue,
            onSilence: onSilence
        )
    }
}

/// The live-subscription half of `HavenNetwork.subscribe`, pulled out on its
/// own so its timing can be tested against a plain publisher rather than a
/// deployment -- see `HavenNetworkTests`.
enum LiveSubscription {
    /// A live subscription answers once and then, correctly, goes quiet
    /// between real changes -- a directory nobody has touched in the last
    /// minute is not unreachable, it is just unchanged. Combine's `.timeout`
    /// resets its timer on every element, so wrapping the whole stream in it,
    /// which is what `HavenNetwork.subscribe` used to do with no branch for
    /// this case, silently completed the stream -- for good, with no error
    /// and no way back -- the first time two pushes landed further apart than
    /// `deadline`. Every caller that reads this way (`DirectoryModel`,
    /// `MyCardModel`, `PersonModel`, `MyNameModel`, `SearchModel`'s facets
    /// read) would then sit on a dead subscription forever, showing whatever
    /// it last received, with nothing on screen saying so: their `onSilence`
    /// handlers all guard on still being in `.loading`, exactly the case this
    /// was failing outside of. The deadline here only bounds the wait for the
    /// *first* answer; nothing past that point carries a deadline of its own,
    /// because nothing should -- a live subscription's job is to sit open and
    /// wait.
    @MainActor
    static func attach<P: Publisher>(
        to stream: P,
        deadline: TimeInterval,
        scheduler: DispatchQueue = .main,
        onValue: @escaping (P.Output) -> Void,
        onSilence: @escaping () -> Void
    ) -> AnyCancellable {
        var answered = false
        let subscription = stream
            .receive(on: scheduler)
            .sink(
                receiveCompletion: { _ in
                    // Any ending is silence, whether or not it already
                    // answered: a live subscription that drops off the
                    // network now is unreachable now, not only at the start.
                    onSilence()
                },
                receiveValue: { value in
                    answered = true
                    onValue(value)
                }
            )
        let watchdog = DispatchWorkItem {
            guard !answered else { return }
            onSilence()
        }
        scheduler.asyncAfter(deadline: .now() + deadline, execute: watchdog)

        return AnyCancellable {
            subscription.cancel()
            watchdog.cancel()
        }
    }
}
