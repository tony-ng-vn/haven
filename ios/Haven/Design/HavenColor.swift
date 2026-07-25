import SwiftUI

// The committed dusk palette. Phase 1 has no light mode, so these are absolute
// values rather than asset-catalogue pairs.
//
// This list is closed. If a surface seems to need a new hue, it almost always
// needs an existing one at a different opacity instead.
enum HavenColor {
    /// Ground. The bottom of every screen's gradient starts here.
    static let night = Color(havenHex: "#0E1123")
    /// Raised surfaces and the top of the background gradient.
    static let dusk = Color(havenHex: "#232A4D")
    /// Horizon warmth. Atmosphere only, never a control.
    static let ember = Color(havenHex: "#E8A87C")
    /// Light, selection, primary accents. A lit star is this colour.
    static let star = Color(havenHex: "#FFD9A0")
    /// Body text.
    static let ink = Color(havenHex: "#F2EFE9")
    /// Secondary text.
    static let muted = Color(havenHex: "#9DA3BE")
    /// Hints and placeholders only. Contrast against Night is borderline, so
    /// this is never body text and never the only carrier of meaning.
    static let faint = Color(havenHex: "#767C9C")
    /// Primary button fill.
    static let cream = Color(havenHex: "#F2E7D5")
    /// Text on `cream`.
    static let creamInk = Color(havenHex: "#1A1730")

    // Derived from white so they read correctly over any part of the gradient.
    // These are opacities, not new hues, which is why they are allowed.

    /// Hairline separators and field borders.
    static let hairline = Color.white.opacity(0.1)
    /// A separator that needs to be seen, such as a mockup's outer edge.
    static let hairlineStrong = Color.white.opacity(0.18)
    /// Field and inset-panel fill.
    static let fill = Color.white.opacity(0.06)
    /// The pressed or hovered state of a row.
    static let rowHighlight = Color.white.opacity(0.04)
}
