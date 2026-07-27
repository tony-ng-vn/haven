import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Haven

// The beacon's pure parts: where a code points, and that the generator actually
// produces one. Whether it scans is a physical question answered by pointing a
// phone at a screen, not by an assertion.

@Suite("Beacon")
struct BeaconTests {
    @Test("a beacon points at Haven's own address")
    func address() {
        #expect(BeaconAddress.url(for: "maya") == "https://inhavens.com/maya")
        // The scheme is in the code and not on the screen: a camera needs it
        // and a reader does not.
        #expect(BeaconAddress.display(for: "maya") == "inhavens.com/maya")
    }

    @Test("the generator produces a code")
    func generates() {
        let image = QRCode.image(for: BeaconAddress.url(for: "maya"))
        #expect(image != nil)
        #expect((image?.width ?? 0) > 0)
        // One pixel per module, so the code is small and square. A 25-module
        // version-2 code is about this size; anything in the hundreds would
        // mean the generator scaled it and the screen would then be scaling a
        // scaled image.
        #expect((image?.width ?? 0) < 100)
        #expect(image?.width == image?.height)
    }

    // The one assertion that says the code is a code rather than a picture of
    // one: read it back the way a camera would and check what comes out is the
    // address that went in.
    @Test("the code reads back as the address it was made from")
    func roundTrips() throws {
        let address = BeaconAddress.url(for: "mayachen")
        let image = try #require(QRCode.image(for: address))

        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        let payloads = features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }

        #expect(payloads == [address])
    }

    /// The raw pixels, which is what "the same code" has to mean here.
    private func bytes(_ image: CGImage?) -> Data? {
        guard let data = image?.dataProvider?.data else { return nil }
        return Data(referencing: data)
    }

    // A beacon that redrew differently between two openings would be a
    // different code for the same person, and anyone who had scanned the first
    // one would have scanned something we no longer produce.
    @Test("the same address always makes the same code")
    func stable() {
        let once = bytes(QRCode.image(for: BeaconAddress.url(for: "maya")))
        let twice = bytes(QRCode.image(for: BeaconAddress.url(for: "maya")))

        #expect(once != nil)
        #expect(once == twice)
    }

    @Test("a different address makes a different code")
    func distinct() {
        let maya = bytes(QRCode.image(for: BeaconAddress.url(for: "maya")))
        let ada = bytes(QRCode.image(for: BeaconAddress.url(for: "ada")))

        #expect(maya != nil)
        #expect(maya != ada)
    }

    /// The invariant the flag actually encodes: a beacon is only shown where the
    /// app and the card page read the same database.
    ///
    /// Tests build in debug, so what can be asserted here is the development
    /// half -- dev deployment, nothing on the web reading it, beacon off. The
    /// release half is the mirror of it and is not reachable from a test run,
    /// which is why both live behind one `#if` in the source rather than being
    /// two values somebody keeps in step by hand.
    @Test("the beacon is only on where the app and the card page agree")
    func flagFollowsTheDeployment() {
        #expect(Config.convexDeploymentUrl.contains("brilliant-puma-925"))
        #expect(FeatureFlags.beaconEnabled == false)
    }

    /// A code carries whatever host Config names, so the two cannot drift into
    /// pointing a scan at a database the app never wrote to.
    @Test("the address a code carries is the configured card host")
    func addressFollowsTheConfiguredHost() {
        #expect(BeaconAddress.url(for: "maya") == "https://\(Config.cardHost)/maya")
    }
}
