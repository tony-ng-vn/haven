import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The QR code on the back of the card.
///
/// Generation only. What colour it is drawn in and how big it gets are the
/// card's business; this hands back the code at its true resolution, one
/// pixel per module, so the screen can scale it with no interpolation and keep
/// the edges square. A blurred module is a module a camera has to guess at.
enum QRCode {
    /// How much of the code can be damaged and still read.
    ///
    /// M tolerates about 15%. Enough for a screen with a fingerprint on it or a
    /// camera at an angle, without the density that H's 30% would add to a code
    /// this short.
    static let correctionLevel = "M"

    /// The code for `text`, at one pixel per module, or nil if CoreImage
    /// refuses it.
    ///
    /// Nil is possible in principle -- the generator is a filter and filters
    /// can fail -- so it is returned rather than force-unwrapped, and the
    /// screen has something honest to show instead of a crash.
    ///
    /// Comes out already in the palette's two ends, because recolouring a
    /// bitmap in SwiftUI can only tint the whole thing at once, and the two
    /// tones have to move independently. Dark on light, which is the polarity
    /// every decoder expects: an inverted code reads on an iPhone and not
    /// reliably anywhere else, and being read by somebody else's phone is this
    /// thing's entire job.
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correctionLevel
        guard let code = filter.outputImage else { return nil }

        let toned = CIFilter.falseColor()
        toned.inputImage = code
        toned.color0 = CIColor(color: UIColor(HavenColor.night))
        toned.color1 = CIColor(color: UIColor(HavenColor.ink))
        guard let output = toned.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

/// Where a beacon points.
///
/// Haven's own address, never a social profile: authorization proves who
/// someone is but cannot construct their profile link in the general case, and
/// a handle is content on the destination rather than the destination itself.
///
/// A debug build makes codes that do not resolve, and that is expected rather
/// than broken: `Config.convexDeploymentUrl` points at the dev deployment while
/// the host below is the site reading production, so a card made in debug has
/// no page. This used to be hidden behind a feature flag. Showing it is better
/// -- the only person holding a debug build is the one who built it, and a flag
/// that hides the card's whole back is a feature nobody can develop.
enum BeaconAddress {
    /// Read from Config, not written here, so the address a code carries always
    /// names the site reading the database this build talks to.
    static var host: String { Config.cardHost }

    /// What the code encodes. The scheme is in the QR and not on the screen,
    /// because a camera needs it and a reader does not.
    static func url(for handle: String) -> String {
        "https://\(host)/\(handle)"
    }

    /// What the card shows under the name.
    static func display(for handle: String) -> String {
        "\(host)/\(handle)"
    }
}
