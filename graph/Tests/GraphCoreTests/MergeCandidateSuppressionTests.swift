import XCTest
@testable import GraphCore

final class MergeCandidateSuppressionTests: XCTestCase {

    private func person(id: String, identifiers: Set<String>) -> Person {
        Person(
            id: id,
            identifiers: identifiers,
            handleRowIDs: [],
            name: nil,
            thumbnailImageData: nil,
            contactCardIDs: [],
            hasContactCard: false
        )
    }

    func testASeparateAnswerSuppressesTheMatchingCandidateRegardlessOfSideOrder() {
        let people = [
            person(id: "p1", identifiers: ["p1", "p1-other"]),
            person(id: "p2", identifiers: ["p2"]),
        ]
        let candidate = MergeCandidate(personID1: "p1", personID2: "p2", sharedName: "Sam")
        // Answer given with the sides in the opposite order from the candidate itself: order
        // must not matter, since the UI can present either side first.
        let answers = [MergeAnswer(identifierA: "p2", identifierB: "p1-other", decision: .separate)]

        let result = MergeCandidateSuppression.apply(candidates: [candidate], people: people, answers: answers)

        XCTAssertTrue(result.isEmpty)
    }

    func testAMergedAnswerAlsoSuppressesDefensively() {
        let people = [
            person(id: "p1", identifiers: ["p1"]),
            person(id: "p2", identifiers: ["p2"]),
        ]
        let candidate = MergeCandidate(personID1: "p1", personID2: "p2", sharedName: "Sam")
        let answers = [MergeAnswer(identifierA: "p1", identifierB: "p2", decision: .merged)]

        let result = MergeCandidateSuppression.apply(candidates: [candidate], people: people, answers: answers)

        XCTAssertTrue(result.isEmpty)
    }

    func testAnUnrelatedAnswerLeavesTheCandidateQueued() {
        let people = [
            person(id: "p1", identifiers: ["p1"]),
            person(id: "p2", identifiers: ["p2"]),
        ]
        let candidate = MergeCandidate(personID1: "p1", personID2: "p2", sharedName: "Sam")
        let answers = [MergeAnswer(identifierA: "unrelated-a", identifierB: "unrelated-b", decision: .separate)]

        let result = MergeCandidateSuppression.apply(candidates: [candidate], people: people, answers: answers)

        XCTAssertEqual(result, [candidate])
    }

    func testNoAnswersLeavesEveryCandidateQueued() {
        let people = [
            person(id: "p1", identifiers: ["p1"]),
            person(id: "p2", identifiers: ["p2"]),
        ]
        let candidate = MergeCandidate(personID1: "p1", personID2: "p2", sharedName: "Sam")

        let result = MergeCandidateSuppression.apply(candidates: [candidate], people: people, answers: [])

        XCTAssertEqual(result, [candidate])
    }
}
