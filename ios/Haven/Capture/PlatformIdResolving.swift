import Foundation

/// Where a captured account's own numeric id comes from, wrapped behind a
/// protocol so `ConvexCaptureSink`'s decision to call it, and not just what
/// it returns, tests without a real network call. `LivePlatformIdResolving`
/// is the one conformer that actually touches a socket.
///
/// A numeric id is what makes a link rename-proof (`PersonReach.openURL`): a
/// handle can be renamed out from under a stored link, but the account itself
/// keeps its id for as long as it exists. Both lookups run before the save
/// they belong to, not after: the server's `saveSharedProfile` looks up the
/// handle's owner id-first, so a resolved platformId is what lets a rename
/// attach to the person who already holds the account instead of quietly
/// creating a twin under the new handle. An id resolved only after the save
/// had already landed (the X lookup's first version) is too late to change
/// which person the save itself wrote to.
protocol PlatformIdResolving: Sendable {
    /// Instagram's own numeric id for a handle, or nil on any failure -- no
    /// network, a bad response, a shape the endpoint did not send this call.
    /// Never throws: a missing id must never delay or fail the save it
    /// belongs to.
    func instagramId(forHandle handle: String) async -> String?

    /// X's own numeric id for a handle, or nil on any failure -- no network,
    /// no connected account server-side, a rate limit, a response that does
    /// not resolve. Same contract as `instagramId`: never throws, never
    /// delays or fails the save it belongs to.
    func xId(forUsername username: String) async -> String?
}

/// What `i.instagram.com/api/v1/users/web_profile_info` sends back. Read
/// defensively: this is an undocumented endpoint of a competitor's app, not a
/// contract Haven can rely on staying the same shape.
struct InstagramWebProfileInfo: Decodable, Equatable {
    struct UserData: Decodable, Equatable {
        let user: User?
    }
    struct User: Decodable, Equatable {
        let id: String?

        // Declared explicitly rather than left to synthesis: a type that
        // supplies its own init(from:) and needs no encode(to:) gives the
        // compiler nothing left to synthesize, so an unqualified
        // `CodingKeys` reference below would otherwise resolve outward to
        // the enclosing type's own CodingKeys instead of failing loudly.
        private enum CodingKeys: String, CodingKey {
            case id
        }

        // Read as either a JSON string or a JSON number: this is an
        // undocumented endpoint with no contract holding it to either shape,
        // and defensive parsing means not silently losing the whole response
        // to a decode error the day it sends one instead of the other.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let string = try? container.decode(String.self, forKey: .id) {
                id = string
            } else if let number = try? container.decode(Int.self, forKey: .id) {
                id = String(number)
            } else {
                id = nil
            }
        }
    }
    let data: UserData?

    /// The numeric id, trimmed, or nil for anything short of a clean value --
    /// missing, blank, or a response shape this call did not send.
    var platformId: String? {
        guard let id = data?.user?.id else { return nil }
        let trimmed = id.trimmedLikeJS
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// What `composio:resolveXUsername` sends back: a discriminated union on
/// `status`, only "resolved" ever carrying a `platformId`.
struct ResolveXUsernameResponse: Decodable, Equatable {
    let status: String
    let platformId: String?

    /// The id, trimmed, or nil for anything short of a clean resolved value.
    var resolvedPlatformId: String? {
        guard status == "resolved" else { return nil }
        let trimmed = platformId?.trimmedLikeJS ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The real resolver: one plain HTTPS request to Instagram's own (undocumented,
/// no-auth) profile endpoint, and one bounded Convex action call for X.
struct LivePlatformIdResolving: PlatformIdResolving {
    /// Short on purpose: this fetch sits in front of a save that must not
    /// wait on it. `HavenNetwork.deadline` (12s) is what a person watches a
    /// spinner for; this is a lookup nobody sees happen at all.
    private static let timeout: TimeInterval = 5
    /// Instagram's own web client id. Public in every browser request their
    /// site itself makes; not a secret Haven is carrying.
    private static let appId = "936619743392459"

    func instagramId(forHandle handle: String) async -> String? {
        let trimmed = handle.trimmedLikeJS
        guard !trimmed.isEmpty,
            let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(
                string: "https://i.instagram.com/api/v1/users/web_profile_info/?username=\(escaped)"
            )
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.setValue(Self.appId, forHTTPHeaderField: "x-ig-app-id")
        guard
            let (body, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let parsed = try? JSONDecoder().decode(InstagramWebProfileInfo.self, from: body)
        else { return nil }
        return parsed.platformId
    }

    func xId(forUsername username: String) async -> String? {
        let trimmed = username.trimmedLikeJS
        guard !trimmed.isEmpty else { return nil }
        // Bounded the same way every Convex action elsewhere in the app is --
        // `value(within:)` already folds a thrown error (no connected
        // account, the action not existing server-side yet) into nil, same
        // as a timeout.
        let work = Task { () throws -> ResolveXUsernameResponse in
            try await convex.action("composio:resolveXUsername", with: ["username": trimmed])
        }
        let response = await work.value(within: .seconds(Self.timeout))
        return response?.resolvedPlatformId
    }
}
