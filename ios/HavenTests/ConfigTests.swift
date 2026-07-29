import Foundation
import Testing

@testable import Haven

// The client configuration that decides which Clerk instance and which Convex
// deployment a build talks to.
//
// These run in DEBUG, which is the point. `Config.clerkPublishableKey` guards
// the same invariant with a `precondition`, but that guard is inside an `#else`
// branch: it cannot fire until somebody cuts a release build, and the first
// release build is the archive on submission day. A placeholder key would have
// survived every green CI run up to that moment. Asserting it here moves the
// failure from "the archive traps on launch" to "the pull request is red".
@Suite("Client configuration")
struct ConfigTests {
    @Test("the production Clerk key is a real one")
    func productionKeyIsNotThePlaceholder() {
        #expect(Config.clerkProductionKey != Config.clerkProductionPlaceholder)
        #expect(Config.clerkProductionKey.hasPrefix("pk_live_"))
    }

    // A Clerk publishable key is the instance's frontend host, base64'd, with a
    // trailing "$". That makes the key self-describing, and this test the only
    // place the pairing is actually checked: the key, `Config.cardHost`, and the
    // Clerk domains in `vercel.json`'s Content-Security-Policy have to name one
    // instance, and nothing but agreement between three files says they do.
    //
    // A mismatched pair compiles, ships, and fails at sign-in with a 401 that
    // reads as "Clerk is down" rather than "these are two different instances".
    @Test("the production key decodes to Clerk's host on the card domain")
    func productionKeyNamesItsOwnHost() throws {
        let host = try #require(clerkHost(from: Config.clerkProductionKey))
        #expect(host == "clerk.\(Config.cardHost)")
    }

    // Development stays development. A `pk_live_` key here would point debug
    // builds -- and the simulator every test runs on -- at the instance real
    // people sign in to.
    @Test("the development key is a development key")
    func developmentKeyIsNotProduction() {
        #expect(Config.clerkDevelopmentKey.hasPrefix("pk_test_"))
    }

    // Which key a build signs in with. Only the DEBUG half is observable from a
    // test bundle, and it is the half worth pinning: tests write real rows, and
    // this is what keeps them out of the production database.
    @Test("this build signs in against development")
    func debugBuildsUseTheDevelopmentInstance() {
        #expect(Config.clerkPublishableKey == Config.clerkDevelopmentKey)
        #expect(Config.convexDeploymentUrl.contains("brilliant-puma-925"))
    }

    /// The host a Clerk publishable key was minted for, or nil if it is not one.
    private func clerkHost(from key: String) -> String? {
        guard let encoded = key.split(separator: "_", maxSplits: 2).last.map(String.init)
        else { return nil }
        // Clerk strips base64 padding; Foundation's decoder requires it.
        let padded = encoded.padding(
            toLength: encoded.count.isMultiple(of: 4)
                ? encoded.count : encoded.count + (4 - encoded.count % 4),
            withPad: "=",
            startingAt: 0
        )
        guard let data = Data(base64Encoded: padded),
            let decoded = String(data: data, encoding: .utf8)
        else { return nil }
        // The trailing "$" is Clerk's, not part of the host.
        return decoded.hasSuffix("$") ? String(decoded.dropLast()) : decoded
    }
}
