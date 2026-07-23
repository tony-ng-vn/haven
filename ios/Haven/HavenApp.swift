import ClerkKit
import ClerkKitUI
import ConvexMobile
import SwiftUI

// Single app-lifetime Convex client, authenticated through Clerk. We use our own
// provider (HavenConvexAuthProvider) rather than the stock ClerkConvexAuthProvider
// so the token is minted from Clerk's "convex" JWT template, matching what the web
// app sends and what convex/auth.config.ts (applicationID "convex") expects.
@MainActor
let convex: ConvexClientWithAuth<String> = {
    let provider = HavenConvexAuthProvider(template: "convex")
    let client = ConvexClientWithAuth(
        deploymentUrl: Config.convexDeploymentUrl,
        authProvider: provider as any AuthProvider<String>
    )
    provider.bind(client: client)
    return client
}()

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
