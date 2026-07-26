import AuthenticationServices
import ClerkKit

/// What a finished authorization handed back.
struct ConnectedAccount {
    /// Present only where the provider sends it. X does; LinkedIn does not,
    /// which is the whole reason its confirm panel exists.
    let username: String?
    let fullName: String
    /// The provider's avatar. Importing it into Haven's storage is a separate
    /// job; it is carried here so that job has something to import.
    let imageUrl: String?
}

enum ContactConnectError: Error {
    case notSignedIn
    /// Backing out of the provider's page. A choice, not a failure.
    case cancelled
}

/// Links an external account to the signed-in Clerk user.
enum ContactConnector {
    @MainActor
    static func connect(_ provider: OAuthProvider) async throws -> ConnectedAccount {
        guard let user = Clerk.shared.user else { throw ContactConnectError.notSignedIn }
        do {
            // Two calls on purpose, and the SDK's own documentation pairs them
            // this way: `createExternalAccount` makes a pending account carrying
            // the provider's authorization URL, and `reauthorize` is what opens
            // it in a browser and waits for the round trip.
            let pending = try await user.createExternalAccount(provider: provider)
            let account = try await pending.reauthorize()
            return ConnectedAccount(
                username: account.username,
                fullName: [account.firstName, account.lastName]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " "),
                imageUrl: account.imageUrl
            )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw ContactConnectError.cancelled
        }
    }
}
