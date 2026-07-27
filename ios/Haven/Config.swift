import Foundation

// Client configuration. Both values are public (safe to ship in the app
// binary): the Clerk publishable key is client-side by design, and the
// Convex deployment URL is public.
//
// - clerkPublishableKey: Clerk dashboard -> API keys (pk_test_... / pk_live_...).
//   One instance across debug and release, and the same one the web app uses,
//   so a person is the same person on both.
// - convexDeploymentUrl: which database the app reads and writes.
//
// The Convex side also needs a JWT template named "convex" in Clerk, and
// CLERK_JWT_ISSUER_DOMAIN set on the Convex deployment (see convex/auth.config.ts).
enum Config {
    static let clerkPublishableKey = "pk_test_dmFsdWVkLWJvbmVmaXNoLTY0LmNsZXJrLmFjY291bnRzLmRldiQ"

    /// The site a beacon's QR sends a stranger to.
    ///
    /// Paired with `convexDeploymentUrl`, and the pairing is the whole point:
    /// the code encodes an address on this host, and whoever scans it gets
    /// whatever database that host reads. Point the app at one database and
    /// the code at a site reading another and every scan resolves to nobody --
    /// or worse, to a different person who happens to hold the same handle
    /// over there.
    static let cardHost = "inhavens.com"

    #if DEBUG
    // Development writes to the dev deployment, so nothing tried here lands in
    // real people's data.
    //
    // Nothing on the web reads this deployment: every Vercel deployment,
    // previews included, is built against production. So a card made in a
    // debug build has no page anywhere, which is exactly why
    // FeatureFlags.beaconEnabled is false in debug. A code that resolves to
    // nobody is not worth showing.
    static let convexDeploymentUrl = "https://brilliant-puma-925.convex.cloud"
    #else
    // What ships: the same database inhavens.com reads. That is what makes a
    // scanned beacon land on the right person's card.
    static let convexDeploymentUrl = "https://third-hound-186.convex.cloud"
    #endif
}
