import XCTest
@testable import GraphCore

/// GuessGrounding is the load-bearing fix for the naming-hallucination bug: a model-guessed
/// name is accepted only if it is actually anchored in the snippet text the model was shown.
/// Every fixture name/snippet pair below is invented -- never real message content.
final class GuessGroundingTests: XCTestCase {

    func testNameAppearingInASelfIntroductionIsGrounded() {
        let snippets = [Snippet(text: "hey its Marlo Quenby from the pottery class", isFromMe: false)]

        XCTAssertTrue(GuessGrounding.isGrounded(name: "Marlo Quenby", snippets: snippets))
    }

    func testNameAppearingInASignOffIsGrounded() {
        let snippets = [Snippet(text: "talk soon - Marlo Quenby", isFromMe: false)]

        XCTAssertTrue(GuessGrounding.isGrounded(name: "Marlo Quenby", snippets: snippets))
    }

    /// The rule is AND, not OR: every significant token of the guessed name must appear, not
    /// just one of them. A first-name-only match ("Marlo" shows up somewhere) is not enough
    /// evidence that "Marlo Quenby" specifically is who this is -- lots of people share a first
    /// name, and accepting a partial match here is exactly the kind of confident-but-thin
    /// inference that produced the original hallucination bug. Rejecting it means some real
    /// guesses (a full name correctly inferred from a first name plus context) are lost too;
    /// that is the intended trade per the brief.
    func testMultiWordNameWhereOnlyTheFirstWordAppearsIsNotGrounded() {
        let snippets = [Snippet(text: "hey Marlo, are we still on for saturday", isFromMe: false)]

        XCTAssertFalse(GuessGrounding.isGrounded(name: "Marlo Quenby", snippets: snippets))
    }

    func testMatchIsCaseAndPunctuationInsensitive() {
        let snippets = [Snippet(text: "MARLO, QUENBY!! are you around", isFromMe: false)]

        XCTAssertTrue(GuessGrounding.isGrounded(name: "marlo quenby", snippets: snippets))
    }

    func testHallucinatedNameWithNoOverlapIsNotGrounded() {
        let snippets = [Snippet(text: "ok see you then", isFromMe: false), Snippet(text: "sounds good", isFromMe: true)]

        XCTAssertFalse(GuessGrounding.isGrounded(name: "Emily Wilson", snippets: snippets))
    }

    /// A single-letter/initial token (length 1) proves nothing: an isolated "a" or "i" shows up
    /// in almost any snippet of ordinary text, so a hallucinated one-letter "name" could pass a
    /// naive substring check purely by chance. Tokens below the minimum length are dropped
    /// before matching; if dropping them leaves nothing left to check, there is no evidence at
    /// all and the guess is rejected rather than vacuously accepted.
    func testBareInitialAloneIsNotGroundedRegardlessOfSnippetContent() {
        let snippets = [Snippet(text: "i had a great time today, see you soon", isFromMe: false)]

        XCTAssertFalse(GuessGrounding.isGrounded(name: "A", snippets: snippets))
    }

    /// Pairs with the case above: once the short/insignificant token is dropped, the remaining
    /// real token still has to be checked and can still pass on its own.
    func testShortInitialIsIgnoredButTheRemainingSurnameStillGrounds() {
        let snippets = [Snippet(text: "quick note from Quenby, running late", isFromMe: false)]

        XCTAssertTrue(GuessGrounding.isGrounded(name: "A Quenby", snippets: snippets))
    }

    /// Ordinary function words ("will", "can", "may", and the like) are common enough in casual
    /// texting that they will show up in almost any conversation whether or not the model ever
    /// intended them as part of a name. Treating them as significant would let a hallucinated
    /// name built entirely out of function words pass grounding by coincidence -- exactly the
    /// failure mode the grounding check exists to close. The cost is real: a person whose actual
    /// name is "Will" or "May" cannot be grounded by their first name alone. That is accepted
    /// per the brief's trade (an unnamed number beats a fabricated identity); a good second/last
    /// name token in the guess would still ground it, per the case above.
    func testGuessBuiltEntirelyOfCommonWordsIsNotGroundedEvenWhenBothWordsLiterallyAppear() {
        let snippets = [Snippet(text: "the bill will be paid tomorrow", isFromMe: false)]

        XCTAssertFalse(GuessGrounding.isGrounded(name: "The Will", snippets: snippets))
    }

    func testEmptyGuessedNameIsNotGrounded() {
        let snippets = [Snippet(text: "hey Marlo Quenby, see you soon", isFromMe: false)]

        XCTAssertFalse(GuessGrounding.isGrounded(name: "", snippets: snippets))
    }

    func testEmptySnippetsNeverGroundAnything() {
        XCTAssertFalse(GuessGrounding.isGrounded(name: "Marlo Quenby", snippets: []))
    }
}
