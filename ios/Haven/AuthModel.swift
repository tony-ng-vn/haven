import Combine
import ConvexMobile
import SwiftUI

// Mirrors the Convex client's auth state into an observable the UI can switch on.
// The client publishes auth state on a Never-failure publisher, so there is no
// error case to handle here.
@MainActor
final class AuthModel: ObservableObject {
    @Published var authState: AuthState<String> = .loading

    init() {
        convex.authState
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { _ in
                LaunchLog.markOnce("first Clerk auth-state resolution")
            })
            .assign(to: &$authState)
    }
}
