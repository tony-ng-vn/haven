import Foundation

// Client configuration. Both values are public (safe to ship in the app
// binary): the Clerk publishable key is client-side by design, and the
// Convex deployment URL is public. Replace both before running.
//
// - clerkPublishableKey: Clerk dashboard -> API keys (pk_test_... / pk_live_...).
// - convexDeploymentUrl: your Convex deployment URL, e.g. https://<name>.convex.cloud
//   (the dev deployment for this project is brilliant-puma-925).
//
// The Convex side also needs a JWT template named "convex" in Clerk, and
// CLERK_JWT_ISSUER_DOMAIN set on the Convex deployment (see convex/auth.config.ts).
enum Config {
    static let clerkPublishableKey = "pk_test_dmFsdWVkLWJvbmVmaXNoLTY0LmNsZXJrLmFjY291bnRzLmRldiQ"
    static let convexDeploymentUrl = "https://brilliant-puma-925.convex.cloud"
}
