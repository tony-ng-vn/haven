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
    /// Connects `provider`, reusing whatever Clerk already holds.
    ///
    /// Linking is not a fresh act every time it is asked for. Someone may have
    /// signed in with this provider, linked it on another device, or got as far
    /// as the browser before the app was killed -- and in Clerk an external
    /// account is a future sign-in connection, so creating a second one is both
    /// wrong and something the API refuses. Three cases, in order:
    ///
    /// - already verified: return it, with no browser trip at all
    /// - half-linked: prepare a fresh authorization for the account that exists
    /// - nothing yet: create one
    @MainActor
    static func connect(_ provider: OAuthProvider) async throws -> ConnectedAccount {
        guard let signedIn = Clerk.shared.user else { throw ContactConnectError.notSignedIn }
        // What Clerk knows now, not what this device last saw. An account linked
        // elsewhere is invisible until the user is reloaded.
        let user = (try? await signedIn.reload()) ?? signedIn

        if let verified = user.verifiedExternalAccounts.first(where: { matches($0, provider) }) {
            return ConnectedAccount(verified)
        }

        do {
            let pending: ExternalAccount
            if let half = user.externalAccounts.first(where: { matches($0, provider) }) {
                // Here but unverified: the browser trip never finished, and the
                // authorization URL it carries has gone stale. Asking for a
                // fresh one beats creating a second account.
                pending = try await half.prepareReauthorization()
            } else {
                pending = try await user.createExternalAccount(provider: provider)
            }
            return ConnectedAccount(try await pending.reauthorize())
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw ContactConnectError.cancelled
        }
    }

    /// Clerk has shipped this field both with and without the `oauth_` prefix,
    /// so match either rather than betting on which shape this SDK sends.
    private static func matches(_ account: ExternalAccount, _ provider: OAuthProvider) -> Bool {
        account.provider == provider.strategy || "oauth_\(account.provider)" == provider.strategy
    }
}

private extension ConnectedAccount {
    init(_ account: ExternalAccount) {
        self.init(
            username: account.username,
            fullName: [account.firstName, account.lastName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            imageUrl: account.imageUrl
        )
    }
}
