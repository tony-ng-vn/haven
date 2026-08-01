import XCTest
@testable import GraphCore

/// Perf smoke, not a correctness check: this asserts the simulation's cost relative to a
/// same-process calibration workload stays within a generous bound, not that any specific
/// behavior is right (see ForceSimulationTests for that).
///
/// Deliberately not a fixed wall-clock threshold: this suite runs on a shared, variably
/// loaded machine, and load only ever inflates a wall-clock measurement, never deflates one
/// -- a fixed millisecond number is exactly the thing that does not survive that (this test
/// measured a mean tick time around 30ms at one point in a session and 194-236ms minutes
/// later, on completely unchanged code, purely from other processes on the same machine).
///
/// Comparing tick() against a calibration workload run right next to it, in the same process,
/// cancels out "how fast is this machine right now" and leaves only "how expensive is this
/// algorithm relative to a known baseline" -- a genuine regression in tick() still moves that
/// ratio, on an idle machine or a loaded one alike. The calibration is bracketed around each
/// individual trial (measured immediately before AND after that trial's tick loop, not once
/// for the whole test): load can change from one moment to the next, and a calibration taken
/// a second or two apart from the tick measurement it is meant to normalize would defeat the
/// point on a bursty machine, not just a steadily busy one.
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

    private func milliseconds(_ elapsed: Duration) -> Double {
        Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) * 1e-15
    }

    /// A fixed-cost, single-threaded, CPU-bound floating-point workload with no relation to
    /// ForceSimulation's own code: sqrt and trig over a deterministic loop, the same flavor of
    /// work `tick()` itself does per node pair. Its only job is to answer "how fast is this
    /// machine right now", so tick()'s own cost can be judged relative to that instead of
    /// against a bare number with no reference point.
    private func calibrationMilliseconds() -> Double {
        let clock = ContinuousClock()
        var accumulator = 0.0
        let elapsed = clock.measure {
            for i in 0..<800_000 {
                let x = Double(i) * 0.0001
                accumulator += (x * x + 1.0).squareRoot() * cos(x)
            }
        }
        // Escaped past the optimizer without ever being asserted on: an unused accumulator is
        // exactly what a release build is entitled to prove dead and delete, which would make
        // the "same machine, same instant" comparison this test depends on meaningless.
        XCTAssertTrue(accumulator.isFinite)
        return milliseconds(elapsed)
    }

    func testPerfSmokeMeanTickTimeAtRealDataScale() {
        let graph = syntheticRealScaleGraph()
        XCTAssertEqual(graph.nodes.count, 630, "fixture drifted from the ~630-node target")
        XCTAssertEqual(graph.edges.count, 549 + 80 + 240, "fixture drifted from the ~850-edge target")

        let tickCount = 100
        let trialCount = 3
        let clock = ContinuousClock()

        // A fresh simulation per trial, all built up front, before any timing starts:
        // reusing one instance across trials would let alpha decay past the settle floor
        // partway through (100 ticks is already about 40% of the way there), turning later
        // trials' tick() calls into free no-ops and making "best of N" measure nothing real.
        let trialSims = (0..<trialCount).map { _ in ForceSimulation(graph: graph, size: CGSize(width: 1200, height: 900)) }

        // The minimum ratio across trials, not the mean: a transient stall (a context switch,
        // a GC pause, a neighboring process's CPU burst) can only ever make one trial's ratio
        // worse than tick()'s true relative cost right now, never better, so the smallest
        // ratio across bracketed trials is the closest read of that true cost.
        var bestRatio = Double.infinity
        var bestMeanPerTick = Double.infinity
        for sim in trialSims {
            let before = calibrationMilliseconds()
            let tickElapsed = clock.measure {
                for _ in 0..<tickCount { sim.tick() }
            }
            let after = calibrationMilliseconds()

            let tickMs = milliseconds(tickElapsed)
            let calibrationMs = (before + after) / 2.0
            let ratio = tickMs / calibrationMs
            if ratio < bestRatio {
                bestRatio = ratio
                bestMeanPerTick = tickMs / Double(tickCount)
            }
        }

        // Visible on every test run, debug or release, so the lead can read real numbers
        // straight from the log without re-running anything.
        print(
            "PERF_SMOKE mean tick time at ~630 nodes / ~850 edges: \(bestMeanPerTick) ms "
                + "(best of \(trialCount), over \(tickCount) ticks); ratio to calibration \(bestRatio)x"
        )

        // Threshold picked with real headroom over the ratio measured across 11 runs in this
        // same session, spanning a huge swing of machine load: system load average 5 to 65
        // (both natural and deliberately induced, up to 20+ background CPU-bound processes),
        // wall-clock mean tick time 28ms to 236ms on completely unchanged code. The ratio
        // itself stayed within roughly 39x-54x across that entire range -- dramatically more
        // stable than either raw millisecond figure alone, which swung more than 8x. 120.0 is
        // about 2.2x above the worst of that observed range: comfortable headroom against
        // ordinary noise, while still catching anything that makes tick() genuinely, not just
        // incidentally, more expensive. This is a smoke test for a pathological regression
        // (tick() becoming many times more expensive), not a tight benchmark -- a real
        // multi-x regression moves the ratio on an idle machine exactly as it would on a
        // loaded one, which a bare wall-clock threshold cannot tell apart from "the machine is
        // just busy right now".
        //
        // Tuned for plain debug `swift test`, the definition-of-done environment: the
        // calibration loop above is simple enough that -O auto-vectorizes it far more
        // aggressively than tick()'s own (branchier, class-based) code, so `swift test -c
        // release` would read an inflated ratio here that says more about that asymmetry than
        // about tick()'s real relative cost. Not a concern for `swift build -c release`
        // (a plain product build, no test execution), only for running this specific test
        // under `-c release`.
        XCTAssertLessThan(
            bestRatio, 120.0,
            "tick cost relative to calibration (\(bestRatio)x) exceeds the smoke threshold -- likely a real regression, not machine load"
        )
    }
}
