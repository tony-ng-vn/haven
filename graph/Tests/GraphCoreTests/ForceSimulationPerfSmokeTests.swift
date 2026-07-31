import XCTest
@testable import GraphCore

/// Perf smoke, not a correctness check: this asserts the simulation stays comfortably fast
/// at real-data scale, not that any specific behavior is right (see ForceSimulationTests for
/// that). Run with `swift test -c release` for a measurement that reflects what pass 2's
/// TimelineView will actually experience; the plain debug `swift test` run also exercises
/// this, just with a much larger margin against the threshold below.
final class ForceSimulationPerfSmokeTests: XCTestCase {

    /// About 630 visible nodes (1 user + 549 persons + 80 live groups) and about 850 edges
    /// (549 oneToOneThread + 80 userGroupMembership, all involvesUser and so excluded from
    /// springs, plus 240 groupMembership springs at 3 members per group), matching the real
    /// graph's rough order of magnitude from PLAN.md. Deterministic: no randomness anywhere,
    /// same generation every run.
    private func syntheticRealScaleGraph() -> Graph {
        let personCount = 549
        let groupCount = 80
        let membersPerGroup = 3

        var nodes: [GraphNode] = [
            GraphNode(id: "user", kind: .user, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: false, degree: personCount + groupCount)
        ]
        for i in 0..<personCount {
            nodes.append(
                GraphNode(id: "person\(i)", kind: .person, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: false, degree: 1)
            )
        }
        for g in 0..<groupCount {
            nodes.append(
                GraphNode(id: "chat:g\(g)", kind: .group, name: nil, thumbnailImageData: nil, hasContactCard: false, isLive: true, degree: membersPerGroup + 1)
            )
        }

        var edges: [GraphEdge] = []
        for i in 0..<personCount {
            edges.append(GraphEdge(nodeIDA: "user", nodeIDB: "person\(i)", source: .imessage, reason: .oneToOneThread, strength: 4, involvesUser: true))
        }
        for g in 0..<groupCount {
            edges.append(GraphEdge(nodeIDA: "user", nodeIDB: "chat:g\(g)", source: .imessage, reason: .userGroupMembership, strength: 2, involvesUser: true))
            for m in 0..<membersPerGroup {
                let personIndex = (g * membersPerGroup + m) % personCount
                edges.append(
                    GraphEdge(nodeIDA: "person\(personIndex)", nodeIDB: "chat:g\(g)", source: .imessage, reason: .groupMembership, strength: 3, involvesUser: false)
                )
            }
        }

        return Graph(nodes: nodes, edges: edges)
    }

    func testPerfSmokeMeanTickTimeAtRealDataScale() {
        let graph = syntheticRealScaleGraph()
        XCTAssertEqual(graph.nodes.count, 630, "fixture drifted from the ~630-node target")
        XCTAssertEqual(graph.edges.count, 549 + 80 + 240, "fixture drifted from the ~850-edge target")

        let sim = ForceSimulation(graph: graph, size: CGSize(width: 1200, height: 900))

        let tickCount = 100
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<tickCount {
                sim.tick()
            }
        }
        let meanMillisecondsPerTick = Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) * 1e-15
        let meanPerTick = meanMillisecondsPerTick / Double(tickCount)

        // Visible on every test run, debug or release, so the lead can read real numbers
        // straight from the log without re-running anything.
        print("PERF_SMOKE mean tick time at ~630 nodes / ~850 edges: \(meanPerTick) ms (over \(tickCount) ticks)")

        XCTAssertLessThan(meanPerTick, 50.0, "mean tick time \(meanPerTick)ms exceeds the 50ms smoke threshold")
    }
}

