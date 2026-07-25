import SwiftUI

// Colour conversion, kept separate from the palette so it can be tested without
// touching SwiftUI.
enum ColorMath {
    typealias RGB = (r: Double, g: Double, b: Double)

    /// Parses a six-digit hex string, with or without a leading "#".
    /// Deliberately strict: the palette is a fixed list of literals, so anything
    /// that fails here is a typo, not a runtime condition to recover from.
    static func rgb(hex: String) -> RGB? {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (
            r: Double((value >> 16) & 0xFF) / 255,
            g: Double((value >> 8) & 0xFF) / 255,
            b: Double(value & 0xFF) / 255
        )
    }

    /// HSL to RGB. The sky carries hues as HSL to match the web renderer, and
    /// SwiftUI only offers HSB, so the conversion has to live here.
    /// Hue is in degrees and wraps; saturation and lightness are 0...1.
    static func rgb(hue: Double, saturation: Double, lightness: Double) -> RGB {
        let h = hue.truncatingRemainder(dividingBy: 360) / 360
        let s = min(max(saturation, 0), 1)
        let l = min(max(lightness, 0), 1)
        guard s > 0 else { return (r: l, g: l, b: l) }

        let c = (1 - abs(2 * l - 1)) * s
        let m = l - c / 2
        let channel = { (offset: Double) -> Double in
            var t = (h + offset).truncatingRemainder(dividingBy: 1)
            if t < 0 { t += 1 }
            if t < 1.0 / 6.0 { return m + c * (6 * t) }
            if t < 1.0 / 2.0 { return m + c }
            if t < 2.0 / 3.0 { return m + c * (4 - 6 * t) }
            return m
        }
        return (r: channel(1.0 / 3.0), g: channel(0), b: channel(-1.0 / 3.0))
    }
}

extension Color {
    /// Only the palette in `HavenColor` should call this. The precondition is
    /// safe because every caller passes a literal that the test suite parses.
    init(havenHex hex: String) {
        guard let c = ColorMath.rgb(hex: hex) else {
            preconditionFailure("Not a six-digit hex colour: \(hex)")
        }
        self.init(red: c.r, green: c.g, blue: c.b)
    }

    /// The sky's seeded hues, which arrive as HSL.
    init(skyHue hue: Double, saturation: Double, lightness: Double, opacity: Double = 1) {
        let c = ColorMath.rgb(hue: hue, saturation: saturation, lightness: lightness)
        self.init(red: c.r, green: c.g, blue: c.b, opacity: opacity)
    }
}
