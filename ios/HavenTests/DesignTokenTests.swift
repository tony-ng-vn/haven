import Foundation
import Testing
@testable import Haven

// Colour parsing and conversion behind the palette. Everything visual about
// the tokens is judged by a human against the SwiftUI previews.

private let tolerance = 1e-9

private func expectClose(_ actual: Double, _ expected: Double, _ label: String) {
    #expect(abs(actual - expected) < tolerance, "\(label): got \(actual), want \(expected)")
}

// MARK: - Colour math

@Suite("Colour math")
struct ColorMathTests {
    @Test("hex parses the committed palette")
    func hexParses() throws {
        let night = try #require(ColorMath.rgb(hex: "#0E1123"))
        expectClose(night.r, 14.0 / 255.0, "night.r")
        expectClose(night.g, 17.0 / 255.0, "night.g")
        expectClose(night.b, 35.0 / 255.0, "night.b")

        let star = try #require(ColorMath.rgb(hex: "FFD9A0"))
        expectClose(star.r, 1, "star.r")
        expectClose(star.g, 217.0 / 255.0, "star.g")
        expectClose(star.b, 160.0 / 255.0, "star.b")
    }

    @Test("hex rejects anything that is not six hex digits")
    func hexRejects() {
        #expect(ColorMath.rgb(hex: "#FFF") == nil)
        #expect(ColorMath.rgb(hex: "0E1123AA") == nil)
        #expect(ColorMath.rgb(hex: "#0E112G") == nil)
        #expect(ColorMath.rgb(hex: "") == nil)
    }

    // The sky's nebulae, giants and majors carry hues as HSL, matching the web
    // renderer. SwiftUI only offers HSB, so the conversion is ours to get right.
    @Test("hsl converts to rgb")
    func hslConverts() {
        let red = ColorMath.rgb(hue: 0, saturation: 1, lightness: 0.5)
        expectClose(red.r, 1, "red.r")
        expectClose(red.g, 0, "red.g")
        expectClose(red.b, 0, "red.b")

        let darkGreen = ColorMath.rgb(hue: 120, saturation: 1, lightness: 0.25)
        expectClose(darkGreen.r, 0, "darkGreen.r")
        expectClose(darkGreen.g, 0.5, "darkGreen.g")
        expectClose(darkGreen.b, 0, "darkGreen.b")

        let grey = ColorMath.rgb(hue: 210, saturation: 0, lightness: 0.5)
        expectClose(grey.r, 0.5, "grey.r")
        expectClose(grey.g, 0.5, "grey.g")
        expectClose(grey.b, 0.5, "grey.b")

        let white = ColorMath.rgb(hue: 40, saturation: 0.8, lightness: 1)
        expectClose(white.r, 1, "white.r")
        expectClose(white.g, 1, "white.g")
        expectClose(white.b, 1, "white.b")
    }

    @Test("hue wraps so a seeded hue of 360 is not black")
    func hueWraps() {
        let at360 = ColorMath.rgb(hue: 360, saturation: 1, lightness: 0.5)
        let at0 = ColorMath.rgb(hue: 0, saturation: 1, lightness: 0.5)
        expectClose(at360.r, at0.r, "wrapped.r")
        expectClose(at360.g, at0.g, "wrapped.g")
        expectClose(at360.b, at0.b, "wrapped.b")
    }
}
