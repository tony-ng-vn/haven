import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Haven

// Colour parsing and conversion behind the palette, and the contrast a token
// has to hold to be text. Everything else visual about the tokens is judged by
// a human against the SwiftUI previews.

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

// MARK: - Contrast

/// The page runs from night at the top toward dusk as it descends, so a colour
/// that reads at the top of a scroll can fail at the bottom. Every one of these
/// is measured against both ends rather than against the one that flatters it.
@Suite("Text contrast")
struct TextContrastTests {
    /// What WCAG asks of text below roughly 18pt, which is all of Haven's.
    static let readable: Double = 4.5

    @Test("supporting text reads against both ends of the page")
    func secondaryText() {
        #expect(contrast(HavenColor.muted, on: HavenColor.night) >= Self.readable)
        #expect(contrast(HavenColor.muted, on: HavenColor.dusk) >= Self.readable)
    }

    @Test("body text reads against both ends of the page")
    func bodyText() {
        #expect(contrast(HavenColor.ink, on: HavenColor.night) >= Self.readable)
        #expect(contrast(HavenColor.ink, on: HavenColor.dusk) >= Self.readable)
    }

    /// Ember is a row title now -- "Delete your account" -- and not only the
    /// colour of an error message, so it has to be readable rather than merely
    /// alarming.
    @Test("the warning colour reads as text, not just as a warning")
    func warningText() {
        #expect(contrast(HavenColor.ember, on: HavenColor.night) >= Self.readable)
        #expect(contrast(HavenColor.ember, on: HavenColor.dusk) >= Self.readable)
    }

    /// Why the group labels and row accessories moved off `faint`: it reads at
    /// the top of the page and fails at the bottom, and the ACCOUNT heading is
    /// at the bottom. Pinned so nobody moves them back.
    @Test("faint is not a colour for text")
    func faintIsNotForText() {
        #expect(contrast(HavenColor.faint, on: HavenColor.night) >= Self.readable)
        #expect(contrast(HavenColor.faint, on: HavenColor.dusk) < Self.readable)
    }

    /// WCAG 2.1 relative luminance and contrast ratio, on the resolved colours
    /// rather than on the hex literals, so this measures what actually draws.
    private func contrast(_ a: Color, on b: Color) -> Double {
        let first = luminance(a), second = luminance(b)
        let lighter = max(first, second), darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: Color) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

@Suite("The star ignition's two numbers")
struct StarIgnitionTests {
    // The finding this pins: the curve was 96 percent done at 0.40s and two
    // separate sleeps held the app's signature moment for the full 0.85s. The
    // curve keeps its shape; only the waiting was cut.
    @Test("waiting on an ignition is shorter than drawing one")
    func holdIsShorterThanTheCurve() {
        #expect(HavenMotion.starIgnitionHold < HavenMotion.starIgnitionDuration)
        // Long enough to read as a beat rather than a flicker. Below about a
        // third of a second the star and the next question arrive together,
        // which is the thing the hold exists to prevent.
        #expect(HavenMotion.starIgnitionHold >= 0.3)
    }

    // Two sleeps, one constant. They are separate jobs -- one settles the
    // figure, the other holds the next question back -- and the review's
    // complaint was that they shared only a number that neither owned.
    @Test("the hold is a token rather than a literal in two places")
    func holdIsShared() {
        #expect(HavenMotion.starIgnitionHold == 0.40)
    }
}
