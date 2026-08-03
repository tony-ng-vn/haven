import XCTest
@testable import GraphCore

final class IdentifierMaskingTests: XCTestCase {

    // MARK: - mask (killlist's original rule, unchanged)

    func testMaskReplacesAllButLastFourCharactersWithX() {
        XCTAssertEqual(IdentifierMasking.mask("+invented5551234821"), "xxxxxxxxxxxxxxx4821")
    }

    func testMaskLeavesAnIdentifierAtOrUnderTheVisibleLengthUnchanged() {
        XCTAssertEqual(IdentifierMasking.mask("4821"), "4821")
        XCTAssertEqual(IdentifierMasking.mask("12"), "12")
    }

    // MARK: - shortSuffix (the disambiguator's compact form)

    func testShortSuffixOnAPhoneShapedIdentifierUsesItsOwnLastFourCharacters() {
        XCTAssertEqual(IdentifierMasking.shortSuffix("+invented5551234821"), "...4821")
    }

    // MARK: - shortSuffix never leaks a full identifier, even when short

    func testShortSuffixMasksEntirelyWhenAtOrUnderTheVisibleLength() {
        XCTAssertEqual(IdentifierMasking.shortSuffix("4821"), "...")
        XCTAssertEqual(IdentifierMasking.shortSuffix("ab"), "...")
    }

    // MARK: - shortSuffix on an email-shaped identifier uses the LOCAL part, not the domain --
    // the case that actually motivates this function: two different invented people who both
    // happen to use the same email provider must not collapse to the same "...com" badge.

    func testShortSuffixOnEmailShapedIdentifiersUsesTheLocalPartNotTheDomain() {
        let personOne = IdentifierMasking.shortSuffix("invented.newyork@example.com")
        let personTwo = IdentifierMasking.shortSuffix("invented.london@example.com")

        XCTAssertEqual(personOne, "...york")
        XCTAssertEqual(personTwo, "...ndon")
        XCTAssertNotEqual(personOne, personTwo, "same domain, different local part -- must not collide")
    }

    func testShortSuffixMasksEntirelyWhenTheLocalPartAloneIsAtOrUnderTheVisibleLength() {
        // Local part "ab" is only 2 characters; the domain must never be borrowed to pad it out.
        XCTAssertEqual(IdentifierMasking.shortSuffix("ab@example.com"), "...")
    }

    // MARK: - never exposes more than the allowed suffix, for a range of identifier shapes

    func testShortSuffixNeverExposesMoreThanTheVisibleSuffixLength() {
        for identifier in ["+invented15550001234", "person.one@example.org", "short@ex.io", "1234567890"] {
            let result = IdentifierMasking.shortSuffix(identifier)
            let visiblePortion = result.hasPrefix("...") ? String(result.dropFirst(3)) : result
            XCTAssertLessThanOrEqual(
                visiblePortion.count, IdentifierMasking.visibleSuffixLength,
                "shortSuffix(\(identifier)) exposed more than \(IdentifierMasking.visibleSuffixLength) characters"
            )
        }
    }
}
