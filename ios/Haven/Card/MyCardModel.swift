import ClerkKit
import Combine
import ConvexMobile
import SwiftUI

/// Whether the card is on screen yet.
enum MyCardLoad: Equatable {
    case loading
    case ready(MyCard)
    case unreachable
}

/// The caller's own card, and every way to change it.
///
/// One model for the whole screen rather than one per field: every edit is the
/// same partial update against the same row, and splitting them would mean six
/// subscriptions to one document.
@MainActor
final class MyCardModel: ObservableObject {
    @Published private(set) var load: MyCardLoad = .loading
    @Published private(set) var isSaving = false
    @Published var failure: String?

    private var cancellable: AnyCancellable?

    init() {
        subscribe()
    }

    init(preview load: MyCardLoad) {
        self.load = load
    }

    var card: MyCard? {
        if case .ready(let card) = load { return card }
        return nil
    }

    func retry() {
        load = .loading
        subscribe()
    }

    private func subscribe() {
        // Live, unlike onboarding's read: this screen is where a card changes,
        // and an edit made on another device should land here rather than wait
        // for a relaunch.
        cancellable = HavenNetwork.subscribe(
            to: "profiles:getMyCard",
            yielding: MyCard?.self
        ) { [weak self] card in
            // A card that came back empty here means the row is gone, which is
            // what deleting an account looks like from this screen.
            self?.load = card.map { .ready($0) } ?? .unreachable
        } onSilence: { [weak self] in
            guard let self, self.load == .loading else { return }
            self.load = .unreachable
        }
    }

    // MARK: - Writes

    func save(_ fields: [String: ConvexEncodable?]) async {
        await write { try await convex.mutation("profiles:updateMyProfile", with: fields) }
    }

    /// Clears a field. Convex distinguishes an absent key from an explicit
    /// null, and only the second one means "remove this".
    func clear(_ field: String) async {
        await save([field: nil as String?])
    }

    /// Uploads a photo and attaches it in one go.
    ///
    /// Two round trips that have to be one action: a blob uploaded and never
    /// attached is an orphan the sweep eventually reclaims, and the person
    /// would have watched a spinner for nothing.
    func setPhoto(_ data: Data) async {
        await write {
            let url: String = try await convex.mutation("profiles:generateUploadUrl")
            let storageId = try await PhotoUpload.send(data, to: url)
            return try await convex.mutation(
                "profiles:updateMyProfile",
                with: ["photoStorageId": storageId]
            )
        }
    }

    /// Deletes the account: the data first, then the identity that owned it.
    /// Returns true once both are gone, so the caller can sign out rather than
    /// sit on a screen with nothing behind it.
    ///
    /// Both halves, because App Store guideline 5.1.1(v) asks for the account
    /// itself and not only its contents. Purging the rows and signing out left
    /// a Clerk user behind that nobody could see and nobody had asked to keep.
    ///
    /// The order is the part worth protecting. The purge needs a signed-in
    /// token, so deleting the identity first would strand every row it was
    /// meant to remove with no way left to reach them. This way the only bad
    /// case is an identity with nothing behind it, and retrying fixes it:
    /// `deleteMyAccount` is idempotent by design, so the second attempt's
    /// purge is a no-op and the deletion gets another go.
    func deleteAccount() async -> Bool {
        isSaving = true
        failure = nil
        let work = Task { () throws -> Bool in
            let _: String? = try await convex.mutation("profiles:deleteMyAccount")
            _ = try await Clerk.shared.user?.delete()
            return true
        }
        let done = await work.value(within: .seconds(HavenNetwork.deadline)) ?? false
        isSaving = false
        if !done {
            failure = "That did not go through. Check your connection and try again."
        }
        return done
    }

    /// Runs a write with the bounded wait and the one failure message the whole
    /// screen shares.
    private func write(_ body: @escaping () async throws -> MyCard) async {
        guard !isSaving else { return }
        isSaving = true
        failure = nil
        let work = Task { try await body() }
        let saved = await work.value(within: .seconds(HavenNetwork.deadline))
        isSaving = false
        guard let saved else {
            failure = "That did not save. Check your connection and try again."
            return
        }
        // The subscription will bring this too, a moment later. Publishing it
        // now is what makes an edit feel like it took rather than like it is
        // being considered.
        load = .ready(saved)
    }
}

/// Puts a photo in Convex storage.
enum PhotoUpload {
    /// What Convex's upload endpoint hands back.
    private struct Response: Decodable {
        let storageId: String
    }

    /// POSTs the bytes and returns the storage id they landed in.
    ///
    /// The content type is declared rather than assumed: Convex stores what
    /// the upload says, and a shared screenshot is usually a PNG, so leaving
    /// the card's JPEG default on it would file the wrong type against the
    /// blob for the life of the row.
    static func send(
        _ data: Data,
        to url: String,
        contentType: String = "image/jpeg"
    ) async throws -> String {
        guard let endpoint = URL(string: url) else {
            throw UploadError.badURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Convex reads the blob's content type from this header, and the photo
        // validator on the other side refuses anything that is not an image.
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.rejected
        }
        return try JSONDecoder().decode(Response.self, from: body).storageId
    }

    enum UploadError: Error {
        case badURL
        case rejected
    }
}
