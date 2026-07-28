import Combine
import ConvexMobile
import SwiftUI

/// Somebody else's card, as `profiles:getByHandle` returns it.
///
/// Deliberately unauthenticated on the server, because this is the same read
/// the public web page makes: every field on it is one a stranger may see. The
/// phone handle is stripped before it leaves, so there is nothing here to be
/// careful with.
struct PublicCard: Decodable, Equatable {
    let handle: String
    let name: String
    var photoUrl: String?
    var city: MyCard.City?
    var handles: [MyCard.Handle] = []
    var primaryPlatform: MyCard.Platform?

    /// The same card type the reveal and My Card draw, so a person you are
    /// about to connect to looks like a person rather than like a form.
    var asCard: MyCard {
        MyCard(
            username: handle,
            name: name,
            photoUrl: photoUrl,
            city: city,
            handles: handles,
            primaryPlatform: primaryPlatform
        )
    }

    var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }
}

/// What `profiles:connect` answers.
struct ConnectOutcome: Decodable, Equatable {
    let status: String
    let personId: String
    let peerUsername: String

    /// True when the pair was already connected, whichever side did it first.
    var wasAlready: Bool { status == "already" }
}

/// Where the connect screen is.
enum ConnectState: Equatable {
    /// Nothing scanned or typed yet. The camera is looking.
    case idle
    case looking
    /// A card, and a person to connect to.
    case found(PublicCard)
    /// A well-formed address that names nobody. Its own state rather than a
    /// failure: the code scanned fine, there is just no card behind it.
    case unknown(String)
    case connecting(PublicCard)
    case connected(ConnectOutcome, PublicCard)
    case failed(String)

    /// Whether the camera should be reading. It stops the moment there is
    /// something on screen to decide about: a viewfinder under a card somebody
    /// is reading would keep firing at codes behind them.
    var isScanning: Bool {
        self == .idle
    }
}

/// Scanning somebody's card and connecting to them.
///
/// The in-person loop: I show you the back of my card, you point a camera at
/// it, we are both in each other's directories. The backend does both sides
/// (PR 126); everything here is getting a handle out of a camera and rendering
/// what the mutation says back.
@MainActor
final class ConnectModel: ObservableObject {
    @Published private(set) var state: ConnectState = .idle
    /// The address somebody typed, for the path a camera cannot take -- a
    /// simulator, a phone with the camera refused, a handle read out loud.
    @Published var typed = ""

    private let isLive: Bool
    private var cancellable: AnyCancellable?
    /// The handle currently being looked up, so a second sighting of the same
    /// code does not start a second read.
    private var looking: String?

    init() {
        isLive = true
    }

    /// A screen in a fixed state that never opens a socket, for previews.
    init(preview state: ConnectState, typed: String = "") {
        isLive = false
        self.state = state
        self.typed = typed
    }

    var canLookUpTyped: Bool {
        ConnectAddress.handle(in: typed) != nil && state != .looking
    }

    /// Starts over, back at the camera.
    func reset() {
        looking = nil
        state = .idle
    }

    /// A code the camera saw.
    ///
    /// A code that is not Haven's is ignored in silence: the camera sees every
    /// code in front of it, and a scanner that complained about the Wi-Fi
    /// sticker on the table would be complaining constantly. A code seen while
    /// there is already something on screen to decide about is ignored too --
    /// the viewfinder is behind a card somebody is reading.
    func scanned(_ raw: String) async {
        guard state.isScanning else { return }
        await look(at: raw)
    }

    /// Looks up whoever this text names, from a camera or from the field.
    func look(at raw: String) async {
        guard let handle = ConnectAddress.handle(in: raw) else { return }
        // The same code, seen again by a camera running at thirty frames a
        // second, is not a second request.
        guard handle != looking else { return }
        looking = handle
        state = .looking
        guard isLive else { return }

        guard let card = await fetch(handle) else {
            state = .unknown(handle)
            return
        }
        state = .found(card)
    }

    /// Connects to whoever is on screen, and says what the server made of it.
    func connect() async {
        guard case .found(let card) = state else { return }
        state = .connecting(card)
        guard isLive else { return }
        let work = Task { () throws -> ConnectOutcome in
            try await convex.mutation("profiles:connect", with: ["username": card.handle])
        }
        guard let outcome = await work.value(within: .seconds(HavenNetwork.deadline)) else {
            // One message for both a dead network and a refusal, because the
            // screen offers the same way forward either way: try again. The
            // refusals the server can give here -- their card is gone, it is
            // your own address -- are all things trying again shows honestly.
            state = .failed("That did not go through. Check your connection and try again.")
            return
        }
        state = .connected(outcome, card)
    }

    /// One read of the public card, or nil when nobody holds the handle.
    ///
    /// Bounded like every other read in the app: the Convex client reconnects
    /// rather than failing, so nothing else would ever end the wait.
    private func fetch(_ handle: String) async -> PublicCard? {
        await withCheckedContinuation { continuation in
            var resumed = false
            cancellable = HavenNetwork.subscribe(
                to: "profiles:getByHandle",
                with: ["handle": handle],
                yielding: PublicCard?.self,
                firstValueOnly: true,
                onValue: { card in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: card)
                },
                onSilence: {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: nil)
                }
            )
        }
    }
}
