import Foundation

// Client configuration. Both values are public (safe to ship in the app
// binary): the Clerk publishable key is client-side by design, and the
// Convex deployment URL is public.
//
// - clerkPublishableKey: Clerk dashboard -> API keys (pk_test_... / pk_live_...).
//   Split by build configuration, and paired with the deployment below: a Clerk
//   instance and a Convex deployment only understand each other's tokens if the
//   deployment's CLERK_JWT_ISSUER_DOMAIN names that instance.
// - convexDeploymentUrl: which database the app reads and writes.
//
// The Convex side also needs a JWT template named "convex" in Clerk, and
// CLERK_JWT_ISSUER_DOMAIN set on the Convex deployment (see convex/auth.config.ts).
enum Config {
    /// The development instance. Fine here and nowhere else: Clerk development
    /// instances cap their user count and are documented as not for production.
    private static let clerkDevelopmentKey =
        "pk_test_dmFsdWVkLWJvbmVmaXNoLTY0LmNsZXJrLmFjY291bnRzLmRldiQ"

    /// The production instance, once it exists.
    ///
    /// Creating it is dashboard and DNS work that no code change can stand in
    /// for: a production Clerk instance needs its own domain, its own Sign in
    /// with Apple credentials from the developer portal, and its own "convex"
    /// JWT template. Three other things move with it, and a build that has this
    /// key but not those three is still broken:
    ///
    ///   1. Vercel's VITE_CLERK_PUBLISHABLE_KEY for production.
    ///   2. CLERK_JWT_ISSUER_DOMAIN on the third-hound-186 Convex deployment.
    ///   3. The Clerk domains in vercel.json's Content-Security-Policy.
    /// The swap, as a procedure rather than a promise. Four edits, and they
    /// have to land together or the build is broken in a way that only shows
    /// once somebody tries to sign in:
    ///
    ///   1. `clerkProductionKey` below, to the `pk_live_` key from the
    ///      production instance's API keys page.
    ///   2. `VITE_CLERK_PUBLISHABLE_KEY` on Vercel, Production environment, to
    ///      the same key.
    ///   3. `CLERK_JWT_ISSUER_DOMAIN` on the `third-hound-186` Convex
    ///      deployment, to the production instance's Frontend API URL.
    ///   4. The three `valued-bonefish-64` entries in `vercel.json`'s
    ///      Content-Security-Policy, to the production Clerk domain. They are
    ///      in `script-src`, `connect-src` and `frame-src`; miss one and
    ///      sign-in fails silently in the browser with a console error nobody
    ///      is watching.
    ///
    /// Do it before real users rather than after. The issuer is half of
    /// `tokenIdentifier`, so every row written against the development
    /// instance is orphaned by the swap -- not lost, but owned by an identity
    /// that no longer signs in.
    ///
    /// The backend track's wave C8 owns the timing; this side is two of the
    /// four edits and neither is safe on its own.
    private static let clerkProductionPlaceholder = "pk_live_REPLACE_BEFORE_SHIPPING"
    private static let clerkProductionKey = clerkProductionPlaceholder

    /// Which key this build signs in with.
    ///
    /// The check is deliberately a trap rather than a warning. A release build
    /// that quietly falls back to the development instance is the worse
    /// outcome by a distance: it works on the way to the App Store, and then
    /// strangers hit a user cap on an instance their accounts cannot be moved
    /// off. Failing on the developer's own first release build is cheap; this
    /// is not reachable from a debug build at all.
    static let clerkPublishableKey: String = {
        #if DEBUG
        return clerkDevelopmentKey
        #else
        precondition(
            clerkProductionKey != clerkProductionPlaceholder
                && clerkProductionKey.hasPrefix("pk_live_"),
            """
            Config.clerkProductionKey is still the placeholder. A release build \
            must sign in against the production Clerk instance -- see the note \
            on clerkProductionKey for the three other places that move with it.
            """
        )
        return clerkProductionKey
        #endif
    }()

    /// The site the card's QR sends a stranger to.
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
    // previews included, is built against production. So a card made in a debug
    // build has no page anywhere, and the code on its back resolves to nobody.
    // Expected rather than broken -- see `BeaconAddress`.
    static let convexDeploymentUrl = "https://brilliant-puma-925.convex.cloud"
    #else
    // What ships: the same database inhavens.com reads. That is what makes a
    // scanned code land on the right person's card.
    static let convexDeploymentUrl = "https://third-hound-186.convex.cloud"
    #endif
}
