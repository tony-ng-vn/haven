import XCTest
@testable import GraphCore

final class NodeLabelTests: XCTestCase {

    private func node(id: String, kind: NodeKind, name: String?) -> GraphNode {
        GraphNode(id: id, kind: kind, name: name, thumbnailImageData: nil, hasContactCard: name != nil, isLive: true, degree: 1)
    }

    func testRealNameWinsEvenWhenAGuessExistsForTheSameKey() {
        let node = node(id: "+14155550001", kind: .person, name: "Alice Anderson")
        let guesses = ["+14155550001": NameGuess(name: "Someone Else")]

        XCTAssertEqual(NodeLabel.resolve(node: node, guesses: guesses), "Alice Anderson")
    }

    func testPersonGuessIsTildePrefixedAndKeyedByTheNodeIDDirectly() {
        let node = node(id: "+14155550002", kind: .person, name: nil)
        let guesses = ["+14155550002": NameGuess(name: "Jordan Rivera")]

        XCTAssertEqual(NodeLabel.resolve(node: node, guesses: guesses), "~Jordan Rivera")
    }

    /// THE discriminator: a group node's own id is "chat:<guid>" everywhere else in the graph
    /// (GraphBuilder, hiddenGroupGUIDs mapping), but GuessEngine/AppModel key a group's guess
    /// as "group:<guid>" (see GuessCandidate's doc comment) -- a deliberately different prefix.
    /// If NodeLabel ever looked guesses up by the raw node id instead of translating the
    /// prefix, this is the one test that would catch it (every other test here uses a person
    /// node, where the two conventions happen to coincide and would never expose the bug).
    func testGroupNodeIDPrefixTranslatesToTheGroupGuessKey() {
        let node = node(id: "chat:g1", kind: .group, name: nil)
        let guesses = ["group:g1": NameGuess(name: "College Friends")]

        XCTAssertEqual(NodeLabel.resolve(node: node, guesses: guesses), "~College Friends")
    }

    func testNoNameAndNoGuessReturnsNil() {
        let node = node(id: "+14155550003", kind: .person, name: nil)

        XCTAssertNil(NodeLabel.resolve(node: node, guesses: [:]))
    }

    func testGroupWithNoGuessAndNoDisplayNameReturnsNil() {
        let node = node(id: "chat:g2", kind: .group, name: nil)

        XCTAssertNil(NodeLabel.resolve(node: node, guesses: ["group:some-other-guid": NameGuess(name: "Unrelated")]))
    }

    /// Exposed publicly so AppModel's candidate assembly calls this exact function to build a
    /// group candidate's cache key, instead of reimplementing the "chat:" -> "group:" string
    /// transform separately -- the two sides of the key can no longer drift apart from each
    /// other since they are, literally, the same code.
    func testGroupGuessKeyTranslatesTheChatPrefix() {
        XCTAssertEqual(NodeLabel.groupGuessKey(forNodeID: "chat:g1"), "group:g1")
    }

    func testGroupGuessKeyLeavesANonChatPrefixedIDUnchanged() {
        XCTAssertEqual(NodeLabel.groupGuessKey(forNodeID: "+14155550004"), "+14155550004")
    }
}
