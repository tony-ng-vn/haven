import ClerkConvex
import ClerkKit
import ClerkKitUI
import ConvexMobile
import SwiftUI

// Single app-lifetime Convex client, authenticated through Clerk. The
// ClerkConvexAuthProvider watches the Clerk session and fetches the "convex"
// JWT template token on its own -- there is no manual login call to make.
@MainActor
let convex = ConvexClientWithAuth(
    deploymentUrl: Config.convexDeploymentUrl,
    authProvider: ClerkConvexAuthProvider()
)

@main
struct HavenApp: App {
    init() {
        Clerk.configure(publishableKey: Config.clerkPublishableKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .prefetchClerkImages()
                .environment(Clerk.shared)
        }
    }
}
