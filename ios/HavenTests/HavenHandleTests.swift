import Foundation
import Testing
@testable import Haven

@Suite("A Haven address")
struct HavenHandleTests {
    // The same fold the server does before it looks anything up. A client that
    // folded differently would show one address and claim another.
    @Test("what gets claimed is trimmed, unprefixed and lower-cased")
    func normalizing() {
        #expect(HavenHandle.normalize("  @MayaChen  ") == "mayachen")
        #expect(HavenHandle.normalize("@@maya") == "maya")
        #expect(HavenHandle.normalize("MAYA_CHEN") == "maya_chen")
    }

    @Test("an address is letters, numbers and underscores, three to twenty-four")
    func wellFormed() {
        #expect(HavenHandle.candidate(from: "maya") == "maya")
        #expect(HavenHandle.candidate(from: "maya_chen2") == "maya_chen2")
        #expect(HavenHandle.candidate(from: "@Maya") == "maya")
        // Too short, too long, and the characters a URL path cannot carry
        // safely at the root of the site.
        #expect(HavenHandle.candidate(from: "ma") == nil)
        #expect(HavenHandle.candidate(from: String(repeating: "a", count: 25)) == nil)
        #expect(HavenHandle.candidate(from: "maya chen") == nil)
        #expect(HavenHandle.candidate(from: "maya-chen") == nil)
        #expect(HavenHandle.candidate(from: "maya.chen") == nil)
        #expect(HavenHandle.candidate(from: "") == nil)
    }

    // Whether a name belongs to the site is the server's call, not the
    // client's: it answers `taken` for one and offers a way around. A client
    // that refused it here would refuse the suggestion too.
    @Test("a name the site keeps for itself is well formed, and the server refuses it")
    func reservedNamesAreNotTheClientsCall() {
        #expect(HavenHandle.candidate(from: "privacy") == "privacy")
        #expect(HavenHandle.candidate(from: "haven") == "haven")
    }

    @Test("the address is exactly what the card's code encodes")
    func matchesTheBeacon() {
        let handle = HavenHandle.candidate(from: "@MayaChen")
        #expect(handle == "mayachen")
        #expect(BeaconAddress.url(for: handle ?? "").hasSuffix("/mayachen"))
    }
}
