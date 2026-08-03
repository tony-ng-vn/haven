import XCTest
@testable import GraphCore

final class HiddenNodeOverrideTests: XCTestCase {

    private func node(id: String, kind: NodeKind) -> GraphNode {
        GraphNode(id: id, kind: kind, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: true, degree: 0)
    }

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

    private func fixtureGraph() -> Graph {
        Graph(
            nodes: [
                node(id: "user", kind: .user),
                node(id: "alice", kind: .person),
                node(id: "bob", kind: .person),
                node(id: "chat:g1", kind: .group),
            ],
            edges: []
        )
    }

    func testPersonHiddenByAnyIdentifierMapsToTheirCurrentNodeID() {
        let people = [
            person(id: "alice", identifiers: ["alice", "alice-old-identifier"]),
            person(id: "bob", identifiers: ["bob"]),
        ]

        let hidden = HiddenNodeOverride.nodeIDs(
            people: people,
            graph: fixtureGraph(),
            // Hidden by the OLD identifier, not the current node id -- exactly the shifting-id
            // case the brief calls out.
            hiddenPersonIdentifiers: ["alice-old-identifier"],
            hiddenGroupGUIDs: []
        )

        XCTAssertEqual(hidden, ["alice"])
    }

    func testHiddenGroupGUIDMapsToItsChatPrefixedNodeIDOnlyIfPresentInThisGraph() {
        let hidden = HiddenNodeOverride.nodeIDs(
            people: [],
            graph: fixtureGraph(),
            hiddenPersonIdentifiers: [],
            hiddenGroupGUIDs: ["g1", "some-guid-not-in-this-graph"]
        )

        XCTAssertEqual(hidden, ["chat:g1"])
    }

    func testCombinesPersonAndGroupHiding() {
        let people = [person(id: "bob", identifiers: ["bob"])]

        let hidden = HiddenNodeOverride.nodeIDs(
            people: people,
            graph: fixtureGraph(),
            hiddenPersonIdentifiers: ["bob"],
            hiddenGroupGUIDs: ["g1"]
        )

        XCTAssertEqual(hidden, ["bob", "chat:g1"])
    }

    func testEmptyOverridesProduceNoHiddenIDs() {
        let hidden = HiddenNodeOverride.nodeIDs(
            people: [person(id: "alice", identifiers: ["alice"])],
            graph: fixtureGraph(),
            hiddenPersonIdentifiers: [],
            hiddenGroupGUIDs: []
        )

        XCTAssertTrue(hidden.isEmpty)
    }
}
