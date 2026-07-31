import XCTest
@testable import GraphCore

final class ForceSimulationTests: XCTestCase {

    // MARK: - Fixture helpers (pure Graph values; no chat.db/Contacts fixture needed)

    private func node(id: String, kind: NodeKind, isLive: Bool = true, degree: Int = 0) -> GraphNode {
        GraphNode(id: id, kind: kind, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: isLive, degree: degree)
    }

    private func edge(_ a: String, _ b: String, reason: EdgeReason, strength: Double, involvesUser: Bool) -> GraphEdge {
        GraphEdge(nodeIDA: a, nodeIDB: b, source: .imessage, reason: reason, strength: strength, involvesUser: involvesUser)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func runToSettled(_ sim: ForceSimulation, maxTicks: Int = 3000) {
        var ticks = 0
        while !sim.isSettled && ticks < maxTicks {
            sim.tick()
            ticks += 1
        }
    }

    // MARK: - Test 1: determinism

    private func determinismFixture() -> Graph {
        var nodes: [GraphNode] = [node(id: "user", kind: .user, degree: 5)]
        for i in 0..<5 {
            nodes.append(node(id: "person\(i)", kind: .person, degree: 2))
        }
        nodes.append(node(id: "chat:g1", kind: .group, isLive: true, degree: 5))

        var edges: [GraphEdge] = []
        for i in 0..<5 {
            edges.append(edge("person\(i)", "chat:g1", reason: .groupMembership, strength: Double(i), involvesUser: false))
            edges.append(edge("user", "person\(i)", reason: .oneToOneThread, strength: 3, involvesUser: true))
        }
        edges.append(edge("user", "chat:g1", reason: .userGroupMembership, strength: 1, involvesUser: true))

        return Graph(nodes: nodes, edges: edges)
    }

    func testDeterminismSameGraphSameSizeTicksTwiceProducesIdenticalPositions() {
        let graph = determinismFixture()
        let size = CGSize(width: 800, height: 800)

        let simA = ForceSimulation(graph: graph, size: size)
        let simB = ForceSimulation(graph: graph, size: size)
        for _ in 0..<50 {
            simA.tick()
            simB.tick()
        }

        XCTAssertEqual(simA.positions.count, simB.positions.count)
        for id in simA.orderedNodeIDs {
            guard let a = simA.positions[id], let b = simB.positions[id] else {
                XCTFail("\(id) missing a position in one of the two runs")
                continue
            }
            XCTAssertEqual(a.x, b.x, "\(id) x diverged between two fresh runs")
            XCTAssertEqual(a.y, b.y, "\(id) y diverged between two fresh runs")
        }

        // Pinned exact values (captured from a real run): guards against a silent behavior
        // change, not just internal self-consistency between simA/simB.
        let person0 = try! XCTUnwrap(simA.positions["person0"])
        XCTAssertEqual(person0.x, 287.83127537443704, accuracy: 0.000001)
        XCTAssertEqual(person0.y, 294.52467139331475, accuracy: 0.000001)
    }

    // MARK: - Test 2: no NaN/inf after 500 ticks, forced collision

    func testNoNaNOrInfiniteAfter500TicksWithForcedCollision() {
        let nodes: [GraphNode] = [
            node(id: "user", kind: .user, degree: 3),
            node(id: "personA", kind: .person, degree: 2),
            node(id: "personB", kind: .person, degree: 2),
            node(id: "chat:g1", kind: .group, isLive: true, degree: 2),
        ]
        let edges: [GraphEdge] = [
            edge("personA", "chat:g1", reason: .groupMembership, strength: 1, involvesUser: false),
            edge("personB", "chat:g1", reason: .groupMembership, strength: 1, involvesUser: false),
            edge("user", "chat:g1", reason: .userGroupMembership, strength: 1, involvesUser: true),
        ]
        let graph = Graph(nodes: nodes, edges: edges)
        let size = CGSize(width: 800, height: 800)

        // Force personA and personB to start at the exact same point: the natural way this
        // happens (two ids landing in the same hash bucket) is not worth hunting for when the
        // seam can construct it directly and deterministically.
        let collisionPoint = CGPoint(x: 400, y: 400)
        let sim = ForceSimulation(
            graph: graph,
            size: size,
            positionOverrides: ["personA": collisionPoint, "personB": collisionPoint]
        )

        for _ in 0..<500 {
            sim.tick()
        }

        // An empty/stub positions dict would make the loop below vacuously true, so pin the
        // expected visible count first: user + personA + personB + chat:g1.
        XCTAssertEqual(sim.positions.count, 4)
        for (id, point) in sim.positions {
            XCTAssertTrue(point.x.isFinite, "\(id) x is not finite: \(point.x)")
            XCTAssertTrue(point.y.isFinite, "\(id) y is not finite: \(point.y)")
        }
        XCTAssertTrue(sim.alpha.isFinite)
    }

    // MARK: - Test 3: settling

    func testAlphaDecaysMonotonicallyAndSettlesThenFreezes() {
        let graph = determinismFixture()
        let sim = ForceSimulation(graph: graph, size: CGSize(width: 800, height: 800))

        var previousAlpha = sim.alpha
        var ticks = 0
        let maxTicks = 3000
        while !sim.isSettled && ticks < maxTicks {
            sim.tick()
            XCTAssertLessThan(sim.alpha, previousAlpha, "alpha must strictly decrease before settling")
            previousAlpha = sim.alpha
            ticks += 1
        }

        XCTAssertTrue(sim.isSettled, "expected to settle within \(maxTicks) ticks, alpha stalled at \(sim.alpha)")
        XCTAssertLessThan(ticks, maxTicks)

        let alphaAtSettle = sim.alpha
        let positionsAtSettle = sim.positions
        for _ in 0..<20 {
            sim.tick()
        }
        XCTAssertEqual(sim.alpha, alphaAtSettle, "alpha must not change once settled")
        for id in sim.orderedNodeIDs {
            XCTAssertEqual(sim.positions[id]?.x, positionsAtSettle[id]?.x, "\(id) drifted after settling")
            XCTAssertEqual(sim.positions[id]?.y, positionsAtSettle[id]?.y, "\(id) drifted after settling")
        }
    }

    // MARK: - Test 4: clustering

    // NOTE on this fixture: no userGroupMembership edges are attached to either group node
    // (unlike every live group in the real graph, which always gets one from GraphBuilder).
    // That is deliberate -- it isolates the forces this test actually cares about (springs,
    // repulsion, centering) -- but it means passing here is not, by itself, evidence about
    // real-data clustering with user edges in the mix.
    //
    // NOTE on restLength coupling: the required assertion below (mean intra-group member
    // distance < mean cross-group distance) only has real margin when restLength is small
    // relative to the initial scatter radius -- a sweep during tuning found the ratio go
    // 0.83 (restLength 60, fails) -> 1.13 (40) -> 1.48 (30) -> 1.87 (20, the shipped value).
    // If restLength is retuned upward against the real ~630-node render and this test goes
    // red, the message will say "clustering failed"; the actual cause will most likely be
    // restLength approaching the scatter radius, not a broken clustering mechanism. The
    // second assertion below (hub separation vs. each member's distance to its own hub) is
    // the more direct read of PLAN.md's actual claim ("people are pulled toward the groups
    // they belong to") and has a much larger, less restLength-sensitive margin.
    func testSettledClustersAreCloserWithinThanAcross() {
        var nodes: [GraphNode] = [node(id: "user", kind: .user, degree: 0)]
        nodes.append(node(id: "chat:groupA", kind: .group, isLive: true, degree: 4))
        nodes.append(node(id: "chat:groupB", kind: .group, isLive: true, degree: 4))
        for i in 0..<4 {
            nodes.append(node(id: "a\(i)", kind: .person, degree: 1))
            nodes.append(node(id: "b\(i)", kind: .person, degree: 1))
        }

        var edges: [GraphEdge] = []
        for i in 0..<4 {
            edges.append(edge("a\(i)", "chat:groupA", reason: .groupMembership, strength: 3, involvesUser: false))
            edges.append(edge("b\(i)", "chat:groupB", reason: .groupMembership, strength: 3, involvesUser: false))
        }

        let graph = Graph(nodes: nodes, edges: edges)
        let sim = ForceSimulation(graph: graph, size: CGSize(width: 800, height: 800))
        runToSettled(sim)
        XCTAssertTrue(sim.isSettled)

        let positions = sim.positions
        let hubA = positions["chat:groupA"]!
        let hubB = positions["chat:groupB"]!
        let aMembers = (0..<4).map { positions["a\($0)"]! }
        let bMembers = (0..<4).map { positions["b\($0)"]! }

        var intraDistances: [Double] = []
        for i in 0..<4 {
            for j in (i + 1)..<4 {
                intraDistances.append(distance(aMembers[i], aMembers[j]))
                intraDistances.append(distance(bMembers[i], bMembers[j]))
            }
        }
        var crossDistances: [Double] = []
        for a in aMembers {
            for b in bMembers {
                crossDistances.append(distance(a, b))
            }
        }

        let meanIntra = intraDistances.reduce(0, +) / Double(intraDistances.count)
        let meanCross = crossDistances.reduce(0, +) / Double(crossDistances.count)
        XCTAssertLessThan(meanIntra, meanCross, "intra-group members (mean \(meanIntra)) should be closer than cross-group (mean \(meanCross))")

        // The structurally direct claim, independent of the restLength-sensitivity above:
        // each hub is further from the other hub than its own members sit from it.
        let meanOwnHubDistance = (aMembers.map { distance($0, hubA) } + bMembers.map { distance($0, hubB) })
            .reduce(0, +) / 8.0
        let hubSeparation = distance(hubA, hubB)
        XCTAssertGreaterThan(
            hubSeparation, meanOwnHubDistance,
            "groups should separate further from each other (hub distance \(hubSeparation)) than their own members sit from their hub (mean \(meanOwnHubDistance))"
        )
    }

    // MARK: - Test 5: user pinned, unsprung person ends further out than a group member

    func testUserPinnedAndUnsprungPersonEndsFurtherFromCenterThanGroupMember() {
        var nodes: [GraphNode] = [node(id: "user", kind: .user, degree: 20)]
        nodes.append(node(id: "lonely", kind: .person, degree: 1))
        nodes.append(node(id: "chat:g1", kind: .group, isLive: true, degree: 6))
        for i in 0..<6 {
            nodes.append(node(id: "member\(i)", kind: .person, degree: 1))
        }
        // A crowd of extra user-only persons: gives "lonely" enough ambient repulsion to be
        // pushed meaningfully outward, the same way it would sit among hundreds of others in
        // the real graph, rather than in an artificially empty room.
        for i in 0..<15 {
            nodes.append(node(id: "crowd\(i)", kind: .person, degree: 1))
        }

        var edges: [GraphEdge] = [
            edge("user", "lonely", reason: .oneToOneThread, strength: 10, involvesUser: true),
        ]
        for i in 0..<6 {
            edges.append(edge("member\(i)", "chat:g1", reason: .groupMembership, strength: 4, involvesUser: false))
        }
        edges.append(edge("user", "chat:g1", reason: .userGroupMembership, strength: 2, involvesUser: true))
        for i in 0..<15 {
            edges.append(edge("user", "crowd\(i)", reason: .oneToOneThread, strength: 5, involvesUser: true))
        }

        let graph = Graph(nodes: nodes, edges: edges)
        let sim = ForceSimulation(graph: graph, size: CGSize(width: 800, height: 800))
        runToSettled(sim)
        XCTAssertTrue(sim.isSettled)

        let positions = sim.positions
        let center = CGPoint(x: 400, y: 400)
        XCTAssertEqual(positions["user"], center, "the user node must be pinned at center after any number of ticks")

        let lonelyDistance = distance(positions["lonely"]!, center)
        for i in 0..<6 {
            let memberDistance = distance(positions["member\(i)"]!, center)
            XCTAssertGreaterThan(
                lonelyDistance, memberDistance,
                "member\(i) (\(memberDistance)) should be pulled closer to center by its group spring than lonely (\(lonelyDistance)), which has no participating spring"
            )
        }
    }

    // MARK: - Test 6: dead group exclusion

    func testDeadGroupAndItsEdgesAreExcludedFromVisibleSet() {
        let nodes: [GraphNode] = [
            node(id: "user", kind: .user, degree: 2),
            node(id: "person0", kind: .person, degree: 1),
            node(id: "chat:live", kind: .group, isLive: true, degree: 1),
            node(id: "chat:dead", kind: .group, isLive: false, degree: 1),
        ]
        let edges: [GraphEdge] = [
            edge("person0", "chat:live", reason: .groupMembership, strength: 2, involvesUser: false),
            edge("person0", "chat:dead", reason: .groupMembership, strength: 2, involvesUser: false),
            edge("user", "chat:live", reason: .userGroupMembership, strength: 1, involvesUser: true),
            edge("user", "chat:dead", reason: .userGroupMembership, strength: 1, involvesUser: true),
        ]
        let graph = Graph(nodes: nodes, edges: edges)
        let sim = ForceSimulation(graph: graph, size: CGSize(width: 800, height: 800))

        XCTAssertFalse(sim.orderedNodeIDs.contains("chat:dead"), "a dead group must not be part of the visible set")
        XCTAssertNil(sim.positions["chat:dead"], "a dead group must have no position")
        XCTAssertNil(sim.radius(for: "chat:dead"), "a dead group must have no radius suggestion")
        XCTAssertEqual(sim.orderedNodeIDs.sorted(), ["chat:live", "person0", "user"])

        sim.tick()
        XCTAssertNil(sim.positions["chat:dead"], "a dead group must stay excluded after ticking")
    }

    // MARK: - Test 7: bounds

    func testAllPositionsStayWithinASaneMultipleOfSizeAfterSettling() {
        var nodes: [GraphNode] = [node(id: "user", kind: .user, degree: 49)]
        for i in 0..<49 {
            nodes.append(node(id: "person\(i)", kind: .person, degree: 1))
        }
        var edges: [GraphEdge] = []
        for i in 0..<49 {
            edges.append(edge("user", "person\(i)", reason: .oneToOneThread, strength: 4, involvesUser: true))
        }
        let graph = Graph(nodes: nodes, edges: edges)
        XCTAssertEqual(graph.nodes.count, 50)

        let size = CGSize(width: 800, height: 800)
        let sim = ForceSimulation(graph: graph, size: size)
        runToSettled(sim)
        XCTAssertTrue(sim.isSettled)

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let bound = 3.0 * Double(max(size.width, size.height))
        for (id, point) in sim.positions {
            let d = distance(point, center)
            XCTAssertLessThan(d, bound, "\(id) ended \(d) from center, further than the \(bound) bound")
        }
    }
}
