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
        // Nothing else belongs here. Configuring Clerk used to happen in this
        // very init -- see LaunchGate's doc comment for why that held up the
        // first frame, and why the fix is not "make configure faster" but "let
        // something Clerk-free paint before it runs at all".
        LaunchLog.markOnce("HavenApp.init")
    }

    var body: some Scene {
        WindowGroup {
            LaunchGate()
        }
    }
}

/// Paints the night background immediately, then configures Clerk behind it
/// before handing off to `RootView`.
///
/// `Clerk.configure` used to run from `HavenApp.init`, which Swift runs before
/// `body` -- and therefore before `WindowGroup`'s content can be evaluated at
/// all -- can run. `configure` is not free: `installConfiguration` in the SDK
/// does real synchronous work (a cache load, keychain reads), so every launch
/// wasted that on top of the app's own root view. But the SDK's actual
/// contract is narrower than "before anything else runs": `Clerk.shared`'s own
/// doc comment says only "before accessing `Clerk.shared`", and asserts in
/// debug builds exactly when that is violated, not any earlier. This view
/// holds that ordering and nothing more: it has no Clerk or Convex dependency
/// of its own, so its first frame costs neither, and `RootView` -- the one
/// thing that touches `Clerk.shared` (via `.environment`) and, through
/// `AuthModel`, the `convex` global -- is not constructed until `configure`
/// has actually returned. The auth gate does not move; it gets an extra guard
/// in front of it, since `RootView` now cannot exist a moment before Clerk can
/// answer for it.
private struct LaunchGate: View {
    @State private var clerk: Clerk?

    var body: some View {
        LaunchLog.markOnce("LaunchGate first body")
        return content
    }

    @ViewBuilder
    private var content: some View {
        if let clerk {
            RootView()
                .prefetchClerkImages()
                .environment(clerk)
        } else {
            LaunchBackground()
                .task {
                    LaunchLog.markOnce("Clerk.configure start")
                    let configured = Clerk.configure(publishableKey: Config.clerkPublishableKey)
                    LaunchLog.markOnce("Clerk.configure end")
                    clerk = configured
                }
        }
    }
}

/// The night sky, with nothing waiting to be explained.
///
/// Not `HavenLoadingScreen`: that one keeps its spinner, because `RootView`'s
/// own `.loading` case is a genuinely open question -- Clerk is configured by
/// the time it can show, and it is waiting on an answer about who, if anyone,
/// is signed in. Here there is no question yet, only a beat before Clerk can
/// be asked one: the sky is the whole design's resting state everywhere else
/// in the app, so a spinner drawn over it at the one moment nothing has gone
/// wrong reads as though something had. `NightBackground` and `DustLayer` are
/// what every other screen sits on (`HavenScreen`'s `.dust` ambient) and pull
/// in nothing from Clerk or Convex, so this view costs neither.
private struct LaunchBackground: View {
    var body: some View {
        ZStack {
            NightBackground()
            DustLayer()
        }
        .ignoresSafeArea()
    }
}
