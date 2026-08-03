import XCTest
@testable import GraphCore

final class GuessPromptTests: XCTestCase {

    // Static failure messages throughout, never interpolating snippet/prompt content: these
    // are synthetic fixture strings, but GuessPrompt is one hop from real message text, so
    // this file holds itself to the same "never print the content" discipline as the actual
    // privacy test (GuessEngineTests).

    func testPersonContextIncludesTheIdentifierAndTheJSONInstruction() {
        let prompt = GuessPrompt.build(
            snippets: [Snippet(text: "hey are we still on for lunch", isFromMe: false)],
            context: .person(identifier: "+14155550001")
        )

        XCTAssertTrue(prompt.contains("+14155550001"), "person context must include the identifier")
        XCTAssertTrue(prompt.contains("\"name\""), "the JSON-format instruction must name the \"name\" field")
        XCTAssertTrue(prompt.contains("\"description\""), "the JSON-format instruction must name the \"description\" field")
    }

    func testGroupContextIncludesKnownMemberNames() {
        let prompt = GuessPrompt.build(
            snippets: [Snippet(text: "who wants pizza tonight", isFromMe: false)],
            context: .group(memberNames: ["Alice Anderson", "Bob Barker"])
        )

        XCTAssertTrue(prompt.contains("Alice Anderson"), "group context must list known member names")
        XCTAssertTrue(prompt.contains("Bob Barker"), "group context must list every known member name")
        XCTAssertTrue(prompt.contains("\"name\""), "the JSON-format instruction must still be present for a group")
    }

    func testSnippetOrderIsPreservedAndSidesAreMarked() {
        let prompt = GuessPrompt.build(
            snippets: [
                Snippet(text: "first message in the sample", isFromMe: false),
                Snippet(text: "second message in the sample", isFromMe: true),
            ],
            context: .person(identifier: "+14155550002")
        )

        guard let firstRange = prompt.range(of: "first message in the sample"),
              let secondRange = prompt.range(of: "second message in the sample") else {
            return XCTFail("both snippets must appear in the prompt")
        }
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound, "snippet order must be preserved")

        // Them:/Me: markers, per the brief -- checked structurally (does a marker immediately
        // precede each snippet), not by re-printing the snippet text in this description.
        let beforeFirst = prompt[..<firstRange.lowerBound]
        let beforeSecond = prompt[..<secondRange.lowerBound]
        XCTAssertTrue(beforeFirst.hasSuffix("Them: ") || beforeFirst.hasSuffix("Them:"), "an inbound snippet must be marked Them:")
        XCTAssertTrue(beforeSecond.hasSuffix("Me: ") || beforeSecond.hasSuffix("Me:"), "an outbound snippet must be marked Me:")
    }

    func testEmptySnippetsStillProducesAWellFormedPrompt() {
        let prompt = GuessPrompt.build(snippets: [], context: .person(identifier: "+14155550003"))

        XCTAssertTrue(prompt.contains("+14155550003"))
        XCTAssertTrue(prompt.contains("\"name\""))
        XCTAssertFalse(prompt.isEmpty)
    }

    // Abstention must be a first-class, explicitly-shaped answer -- these two assertions are
    // the actual fix for the root cause (GuessPrompt used to forbid refusing outright).
    func testPromptOffersAnExplicitAbstentionShapeRatherThanForbiddingIt() {
        let prompt = GuessPrompt.build(
            snippets: [Snippet(text: "ok see you then", isFromMe: false)],
            context: .person(identifier: "+14155550004")
        )

        XCTAssertTrue(prompt.contains("{\"name\": \"\", \"description\": \"\"}"), "the prompt must give the model an explicit empty-name shape for 'I don't know'")
        XCTAssertFalse(prompt.contains("still return your best guess rather than refusing"), "the old instruction that forbade abstention must be gone")
    }
}
