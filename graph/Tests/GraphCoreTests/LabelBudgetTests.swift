import XCTest
@testable import GraphCore

final class LabelBudgetTests: XCTestCase {

    private func node(id: String, kind: NodeKind, degree: Int) -> GraphNode {
        GraphNode(id: id, kind: kind, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: true, degree: degree)
    }

    func testSelectsTopFortyByDegreeExcludingUser() {
        // 45 person nodes with distinct degrees 1...45, plus the user (highest "degree" of
        // all, which must never matter since the user is excluded outright).
        var nodes: [GraphNode] = [node(id: "user", kind: .user, degree: 999)]
        for i in 1...45 {
            nodes.append(node(id: "person\(i)", kind: .person, degree: i))
        }

        let selected = LabelBudget.selectedNodeIDs(nodes: nodes, limit: 40)

        XCTAssertEqual(selected.count, 40)
        XCTAssertFalse(selected.contains("user"), "the user must never be a label candidate")
        // The top 40 by degree are persons 6...45 (degrees 6 through 45).
        for i in 6...45 {
            XCTAssertTrue(selected.contains("person\(i)"), "person\(i) (degree \(i)) should be in the top 40")
        }
        for i in 1...5 {
            XCTAssertFalse(selected.contains("person\(i)"), "person\(i) (degree \(i)) should not be in the top 40")
        }
    }

    func testTiesBrokenDeterministicallyByID() {
        // Three nodes tied at degree 5, budget of 2: the selection must be the same set
        // every time, decided by id, not by array order or set iteration order.
        let nodes: [GraphNode] = [
            node(id: "zeta", kind: .person, degree: 5),
            node(id: "alpha", kind: .person, degree: 5),
            node(id: "middle", kind: .person, degree: 5),
        ]

        let selected = LabelBudget.selectedNodeIDs(nodes: nodes, limit: 2)

        XCTAssertEqual(selected, ["alpha", "middle"], "ties should resolve to the two lexicographically smallest ids")
    }

    func testFewerNodesThanLimitSelectsAllNonUserNodes() {
        let nodes: [GraphNode] = [
            node(id: "user", kind: .user, degree: 100),
            node(id: "chat:g1", kind: .group, degree: 3),
            node(id: "person1", kind: .person, degree: 1),
        ]

        let selected = LabelBudget.selectedNodeIDs(nodes: nodes, limit: 40)

        XCTAssertEqual(selected, ["chat:g1", "person1"])
    }
}
