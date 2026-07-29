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
//
// The three keys below are `internal` rather than `private` so `ConfigTests`
// can assert on them. That is the whole reason, and it is worth the widening:
// the `precondition` further down guards the same invariant but lives in an
// `#else`, so it cannot fire until the first release build -- which is the
// archive on submission day. A test fires on every commit instead.
enum Config {
    /// The development instance. Fine here and nowhere else: Clerk development
    /// instances cap their user count and are documented as not for production.
    static let clerkDevelopmentKey =
        "pk_test_dmFsdWVkLWJvbmVmaXNoLTY0LmNsZXJrLmFjY291bnRzLmRldiQ"

    /// What `clerkProductionKey` held until the production instance existed.
    /// Kept as a named constant rather than deleted: it is what the release
    /// build's `precondition` and `ConfigTests` both compare against, so the
    /// guard against regressing to a placeholder survives the placeholder.
    static let clerkProductionPlaceholder = "pk_live_REPLACE_BEFORE_SHIPPING"

    /// The `clerk.inhavens.com` instance. Publishable, so shipping it in the
    /// binary is the intended use rather than a leak -- it is the base64 of the
    /// instance's own frontend host, which anybody can read off the website.
    /// The secret key is its counterpart and lives only in Convex's env.
    ///
    /// The swap to this instance is four edits, and no single one of them
    /// works alone. A build carrying this key but missing any of
    /// the others is broken in the way that only shows when somebody tries to
    /// sign in -- a 401 that reads as "Clerk is down" rather than as a pair of
    /// systems pointed at different instances. Where each stands:
    ///
    ///   1. DONE -- this key.
    ///   2. DONE -- the Clerk domains in `vercel.json`'s
    ///      Content-Security-Policy. Both instances are named, in `script-src`,
    ///      `connect-src` and `frame-src`, so the dev instance keeps working
    ///      for previews. Drop the `valued-bonefish-64` entries once nothing
    ///      needs it.
    ///   3. DONE -- `VITE_CLERK_PUBLISHABLE_KEY` on Vercel's Production
    ///      environment, per `todo.md`.
    ///   4. DONE -- `CLERK_JWT_ISSUER_DOMAIN` on the `third-hound-186` Convex
    ///      deployment, set to `https://clerk.inhavens.com` by the backend
    ///      track on 2026-07-29.
    ///
    /// Believed rather than verified for 3 and 4: both are dashboard state this
    /// repo cannot read, and `.env.local`'s deploy key returns 401, so the
    /// record in `todo.md` is the only evidence. What is genuinely untested is
    /// the whole of it -- nobody has signed in against production since. The
    /// production instance also needs a JWT template named "convex", or the
    /// issuer is right and the tokens carry nothing Convex can use.
    ///
    /// And before any of it is worth doing, the production instance has to
    /// exist properly: its own domain, its own Sign in with Apple credentials
    /// from the Apple developer portal, and its own JWT template named
    /// "convex". Without the template the issuer is right and the tokens still
    /// carry nothing Convex can use.
    ///
    /// Do it before real users rather than after. The issuer is half of
    /// `tokenIdentifier`, so every row written against the development
    /// instance is orphaned by the swap -- not lost, but owned by an identity
    /// that no longer signs in.
    static let clerkProductionKey = "pk_live_Y2xlcmsuaW5oYXZlbnMuY29tJA"

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
    // Production inhavens.com does not read this deployment, so a card made in
    // a debug build has no page there and the code on its back resolves to
    // nobody. Expected rather than broken -- see `BeaconAddress`.
    //
    // Vercel *previews* do read it: they stopped deploying Convex and now build
    // against VITE_CONVEX_URL, which is set to this deployment. So a debug-build
    // card does resolve on a preview url, which is the only place to see one.
    static let convexDeploymentUrl = "https://brilliant-puma-925.convex.cloud"
    #else
    // What ships: the same database inhavens.com reads. That is what makes a
    // scanned code land on the right person's card.
    static let convexDeploymentUrl = "https://third-hound-186.convex.cloud"
    #endif
}
