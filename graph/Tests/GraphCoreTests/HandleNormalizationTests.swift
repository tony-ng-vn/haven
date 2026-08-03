import XCTest
@testable import GraphCore

final class HandleNormalizationTests: XCTestCase {

    func testNormalizationTable() {
        let cases: [(input: String, expected: NormalizedIdentifier)] = [
            // Passthrough E.164: already correctly formed, unchanged.
            ("+14155550132", .phone("+14155550132")),
            // Parens, space, hyphen stripped, bare 10 digits, +1 default applied.
            ("(415) 555-0132", .phone("+14155550132")),
            // Bare 10-digit.
            ("4155550132", .phone("+14155550132")),
            // 1-prefixed 11-digit.
            ("14155550132", .phone("+14155550132")),
            // 5-digit shortcode: not a phone shape, stays .other unchanged.
            ("12345", .other("12345")),
            // Alphanumeric sender id: contains a letter, stays .other unchanged.
            ("AB1234", .other("AB1234")),
            // Mixed-case email with surrounding whitespace: lowercased and trimmed.
            (" Bob@EXAMPLE.com ", .email("bob@example.com")),
        ]

        for testCase in cases {
            let actual = HandleNormalization.normalize(testCase.input)
            XCTAssertEqual(actual, testCase.expected, "normalizing \"\(testCase.input)\"")
        }
    }
}
