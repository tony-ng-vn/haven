import Foundation
import Testing
@testable import Haven

@Suite("Reading a Haven address")
struct ConnectAddressTests {
    // The three shapes that actually arrive: what a card's code carries, what a
    // paste from a browser bar looks like, and a handle somebody read out.
    @Test("every shape of a Haven address gives up the same handle")
    func acceptsEveryShape() {
        let inputs = [
            "https://inhavens.com/mayachen",
            "http://inhavens.com/mayachen",
            "HTTPS://INHAVENS.COM/mayachen",
            "https://www.inhavens.com/mayachen",
            "inhavens.com/mayachen",
            "  https://inhavens.com/mayachen  ",
            "mayachen",
            "@mayachen",
        ]
        for input in inputs {
            #expect(ConnectAddress.handle(in: input) == "mayachen", "\(input)")
        }
    }

    // A camera sees every code in front of it. Most of them are not Haven's,
    // and the whole first job here is refusing them.
    @Test("a code that is not a Haven card is refused")
    func refusesStrangers() {
        let inputs = [
            "https://example.com/mayachen",
            // A suffix that is not a dot boundary is somebody else's host.
            "https://inhavens.com.example.test/mayachen",
            "https://notinhavens.com/mayachen",
            // Haven's own widget url names a screen, not a person.
            "haven://beacon",
            "WIFI:S:CoffeeShop;T:WPA;P:hunter2;;",
            "mailto:maya@example.com",
            "tel:+84901234567",
            "",
            "   ",
            "@",
        ]
        for input in inputs {
            #expect(ConnectAddress.handle(in: input) == nil, "\(input)")
        }
    }

    // The card page lives at the root of the site, so anything deeper is one of
    // the site's own pages rather than somebody's card.
    @Test("only the root of the site names a card")
    func onlyTheRoot() {
        #expect(ConnectAddress.handle(in: "https://inhavens.com/") == nil)
        #expect(ConnectAddress.handle(in: "https://inhavens.com") == nil)
        #expect(ConnectAddress.handle(in: "https://inhavens.com/a/b") == nil)
    }

    // Query strings and fragments are the share sheet's noise, not part of who
    // this is.
    @Test("tracking noise does not become part of the handle")
    func ignoresQueryAndFragment() {
        #expect(ConnectAddress.handle(in: "https://inhavens.com/mayachen?s=11") == "mayachen")
        #expect(ConnectAddress.handle(in: "https://inhavens.com/mayachen#card") == "mayachen")
        #expect(ConnectAddress.handle(in: "https://inhavens.com/mayachen/") == "mayachen")
    }

    // Whether a handle is well formed, and whether anybody holds it, are both
    // the server's answer. This one only decides whether the text names Haven.
    @Test("a handle the server will refuse still reads as a handle")
    func shapeIsNotThisJob() {
        #expect(ConnectAddress.handle(in: "https://inhavens.com/NOT_A_HANDLE!") == "NOT_A_HANDLE!")
        #expect(ConnectAddress.handle(in: "ab") == "ab")
    }

    // The address a card's own code carries has to scan into the app that made
    // it, or the whole loop is broken by a constant nobody kept in step.
    @Test("what BeaconAddress writes is what this reads")
    func roundTripsTheBeacon() {
        #expect(ConnectAddress.handle(in: BeaconAddress.url(for: "mayachen")) == "mayachen")
        #expect(ConnectAddress.handle(in: BeaconAddress.display(for: "mayachen")) == "mayachen")
    }
}
