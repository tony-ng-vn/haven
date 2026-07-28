import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Haven

// The code's pure parts: where it points, and that the generator actually
// produces one. Whether it scans is a physical question answered by pointing a
// phone at a screen, not by an assertion.

@Suite("Beacon")
struct BeaconTests {
    @Test("a code points at Haven's own address")
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

    // A code that redrew differently between two turns of the card would be a
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

    /// Why a code made in a debug build does not resolve, asserted so it stays
    /// the reason. The app writes here and the card page reads production, so
    /// the two are deliberately different databases. If these ever became the
    /// same one, a developer's throwaway test card would be a real person's
    /// card and this test is what would notice.
    @Test("a debug build writes somewhere the card page does not read")
    func debugWritesToTheDevelopmentDeployment() {
        #expect(Config.convexDeploymentUrl.contains("brilliant-puma-925"))
    }

    /// A code carries whatever host Config names, so the two cannot drift into
    /// pointing a scan at a database the app never wrote to.
    @Test("the address a code carries is the configured card host")
    func addressFollowsTheConfiguredHost() {
        #expect(BeaconAddress.url(for: "maya") == "https://\(Config.cardHost)/maya")
    }
}
