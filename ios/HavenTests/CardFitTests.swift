import SwiftUI
import Testing
import UIKit

@testable import Haven

// The card is a fixed shape holding text that is not. Every failure in here is
// the same failure: something that fits at the default text size on the phone
// it was designed on, and stops fitting somewhere else. None of them crash, so
// none of them show up anywhere but in a screenshot nobody took.

@Suite("Card fit")
struct CardFitTests {
    /// The narrowest Haven supports, which is where the foot is tightest.
    static let smallPhoneWidth: CGFloat = 375
    /// A 12.9 inch iPad on its side: the widest thing that can ask the card how
    /// big it would like to be.
    static let largeTabletWidth: CGFloat = 1366
    static let largeTabletHeight: CGFloat = 1024

    private static func cardWidth(screen: CGFloat) -> CGFloat {
        min(screen - 2 * CardObjectMetrics.screenInset, CardObjectMetrics.maxWidth)
    }

    // MARK: - The contact row

    /// Four marks and three gaps inside the card's foot.
    ///
    /// This is the one that was already broken: at 44pt across they needed
    /// 212pt inside about 210pt of face, so the row overflowed its own card on
    /// every phone before anybody touched Dynamic Type.
    @Test("the contact marks fit the foot at every text size")
    func contactsFit() {
        let face = Self.cardWidth(screen: Self.smallPhoneWidth) - 2 * CardMetrics.footInset
        // Roughly the range `@ScaledMetric` spans from the smallest text size
        // to accessibility 5.
        for scaled in stride(from: 20.0, through: 120.0, by: 4.0) {
            let diameter = CardMetrics.fittedContactDiameter(scaled: scaled, fitting: face, count: 4)
            let row = 4 * diameter + 3 * CardMetrics.contactGap
            #expect(row <= face, "a \(diameter)pt mark needs \(row)pt of \(face)pt")
        }
    }

    /// Shrinking to fit has a floor: below it the marks are no longer marks.
    @Test("the marks never shrink to nothing, however tight the card")
    func contactsHaveAFloor() {
        let diameter = CardMetrics.fittedContactDiameter(scaled: 100, fitting: 40, count: 4)
        #expect(diameter >= CardMetrics.contactDiameterFloor)
    }

    /// The cap is a ceiling, not a size. At the default text size the marks are
    /// whatever `@ScaledMetric` asked for.
    @Test("at the usual text size the marks are the size they were designed")
    func contactsUseTheDesignedSize() {
        let face = Self.cardWidth(screen: Self.smallPhoneWidth) - 2 * CardMetrics.footInset
        let diameter = CardMetrics.fittedContactDiameter(
            scaled: CardMetrics.contactDiameter,
            fitting: face,
            count: 4
        )
        #expect(diameter == CardMetrics.contactDiameter)
    }

    // MARK: - The card itself

    /// `TARGETED_DEVICE_FAMILY` is "1,2", so this ships on iPad. Without a cap
    /// the width is the screen's, the height follows from the aspect, and a
    /// 12.9 inch iPad on its side computes a card taller than the display --
    /// which puts every row under it out of reach.
    @Test("the card fits an iPad on its side")
    func cardFitsATablet() {
        let width = Self.cardWidth(screen: Self.largeTabletWidth)
        let height = width / CardObjectMetrics.aspect
        #expect(height < Self.largeTabletHeight)
    }

    /// The cap must not bind on a phone, or it would take the card away from
    /// the edges it was drawn against.
    @Test("the cap does not touch the card on a phone")
    func capIsTabletOnly() {
        let inset = Self.smallPhoneWidth - 2 * CardObjectMetrics.screenInset
        #expect(inset < CardObjectMetrics.maxWidth)
    }

    // MARK: - The figure

    /// A long name at an accessibility size used to squeeze the figure toward
    /// nothing, and the failure looked like the sky quietly not being there
    /// rather than like text overflowing.
    @Test("the figure keeps a band however much room the name takes")
    func figureSurvivesALongName() {
        let height: CGFloat = 400
        for foot in stride(from: 0.0, through: 600.0, by: 20.0) {
            let band = CardMetrics.figureBandHeight(cardHeight: height, footHeight: foot)
            #expect(band >= CardMetrics.figureBandFloor * height)
            #expect(band <= height)
        }
    }

    /// With room to spare the band is simply what is left, not the floor.
    @Test("a short name leaves the figure everything it does not use")
    func figureTakesWhatIsLeft() {
        let band = CardMetrics.figureBandHeight(cardHeight: 400, footHeight: 80)
        #expect(band == 400 - 80 - CardMetrics.footInset - CardMetrics.figureGap)
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
