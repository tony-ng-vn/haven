import ClerkKit
@preconcurrency import ConvexMobile

// Haven-owned auth provider. It is a faithful copy of clerk-convex-swift's
// ClerkConvexAuthProvider (0.1.0) with one deliberate change: it fetches Clerk's
// "convex" JWT template token instead of the default session token.
//
// Why: our Convex deployment sets applicationID "convex" (convex/auth.config.ts),
// and the web app authenticates via ConvexProviderWithClerk, which fetches the
// "convex" template token (getToken({ template: "convex" })). The stock
// ClerkConvexAuthProvider calls session.getToken() with no template, so its token
// carries a different audience and Convex rejects it -- the query then hangs
// forever instead of returning. Requesting the same template realigns the audience.
//
// The refresh path also re-fetches the templated token: Clerk session tokens expire
// roughly every 60s, and pushing a refreshed *default* token to Convex would break
// auth after the first minute.
@MainActor
final class HavenConvexAuthProvider: AuthProvider {
    typealias T = String

    enum AuthError: Error {
        case clerkNotLoaded
        case noActiveSession
        case tokenRetrievalFailed(String)
    }

    private let template: String
    private var onIdToken: (@Sendable (String?) -> Void)?
    private var tokenRefreshListenerTask: Task<Void, Never>?
    private var sessionSyncTask: Task<Void, Never>?
    private weak var client: ConvexClientWithAuth<String>?

    init(template: String = "convex") {
        self.template = template
    }

    /// Binds a Convex client and starts syncing Clerk session state into it.
    /// Mirrors the ClerkConvexAuthProvider convenience init's bind call.
    func bind(client: ConvexClientWithAuth<String>) {
        self.client = client
        startSessionSync()
    }

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        try await authenticate(onIdToken: onIdToken)
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        try await authenticate(onIdToken: onIdToken)
    }

    func logout() async throws {
        tokenRefreshListenerTask?.cancel()
        tokenRefreshListenerTask = nil
        onIdToken = nil
        try await Clerk.shared.auth.signOut()
    }

    nonisolated func extractIdToken(from authResult: String) -> String {
        authResult
    }

    // MARK: - Private

    private func authenticate(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        self.onIdToken = onIdToken
        let token = try await fetchToken()
        setupTokenRefreshListener()
        return token
    }

    private func fetchToken() async throws -> String {
        guard Clerk.shared.isLoaded else {
            throw AuthError.clerkNotLoaded
        }
        guard let session = Clerk.shared.session, session.status == .active else {
            throw AuthError.noActiveSession
        }
        guard let token = try await session.getToken(.init(template: template)) else {
            throw AuthError.tokenRetrievalFailed("Token returned nil")
        }
        return token
    }

    private func setupTokenRefreshListener() {
        tokenRefreshListenerTask?.cancel()
        tokenRefreshListenerTask = Task { [weak self] in
            guard let self else { return }
            for await event in Clerk.shared.auth.events {
                guard !Task.isCancelled else { break }
                switch event {
                case .tokenRefreshed:
                    // Re-fetch the templated token; the event's token is the default one.
                    if let token = try? await fetchToken() {
                        onIdToken?(token)
                    }
                default:
                    break
                }
            }
        }
    }

    private func startSessionSync() {
        sessionSyncTask?.cancel()
        sessionSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await syncSession(newSession: Clerk.shared.session)
            for await event in Clerk.shared.auth.events {
                guard !Task.isCancelled else { break }
                switch event {
                case .sessionChanged(let oldSession, let newSession):
                    await syncSession(oldSession: oldSession, newSession: newSession)
                default:
                    break
                }
            }
        }
    }

    private func syncSession(oldSession: Session? = nil, newSession: Session?) async {
        guard let client else { return }
        if shouldLogin(oldSession: oldSession, newSession: newSession) {
            _ = await client.loginFromCache()
        } else if shouldLogout(oldSession: oldSession, newSession: newSession) {
            await client.logout()
        }
    }

    private func shouldLogin(oldSession: Session?, newSession: Session?) -> Bool {
        newSession?.status == .active
            && (oldSession?.status != .active || oldSession?.id != newSession?.id)
    }

    private func shouldLogout(oldSession: Session?, newSession: Session?) -> Bool {
        oldSession?.id != nil && newSession == nil
    }
}
