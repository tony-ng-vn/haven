import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The QR code behind the beacon.
///
/// Generation only. What colour it is drawn in and how big it gets are the
/// screen's business; this hands back the code at its true resolution, one
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
    /// reliably anywhere else, and this is the one screen whose entire job is
    /// being read by somebody else's phone.
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
enum BeaconAddress {
    static let host = "inhavens.com"

    /// What the code encodes. The scheme is in the QR and not on the screen,
    /// because a camera needs it and a reader does not.
    static func url(for handle: String) -> String {
        "https://\(host)/\(handle)"
    }

    /// What the screen shows under the name.
    static func display(for handle: String) -> String {
        "\(host)/\(handle)"
    }
}
