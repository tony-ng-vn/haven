import Foundation
import CoreGraphics

/// Deterministic force-directed layout over a Graph. Pure state and stepping logic, no UI:
/// pass 2 (SwiftUI) ticks this once per frame from a TimelineView and reads `positions`.
/// The assembly animation IS this simulation settling from scattered starting points.
public final class ForceSimulation {

    /// All tunable constants in one place so the lead can retune against the real ~630-node
    /// render without hunting through the physics. Values below were chosen against small
    /// synthetic fixtures (tens of nodes); repulsion in particular is O(n^2) in effect as
    /// well as cost, so it will likely need to come down for the real graph's density.
    private enum Tuning {
        /// Coulomb-like pairwise push between every two visible non-user nodes.
        static let repulsionConstant: Double = 2000

        /// Hooke's-law constant applied on top of the per-edge strength scaling below.
        static let springConstant: Double = 0.02

        /// Distance a spring settles toward when its pull and the ambient repulsion balance.
        static let restLength: Double = 20

        /// Pulls every non-user visible node toward the simulation center, proportional to
        /// distance (a spring to a fixed point, not a constant force). Without this, a node
        /// with no participating springs (e.g. a person whose only edge is to the user, which
        /// is excluded from springs) has nothing to anchor it and repulsion alone would push
        /// it outward forever.
        static let centeringStrength: Double = 0.0003

        /// Fraction of velocity kept between ticks (friction is 1 - this). Raised from an
        /// earlier 0.5 once alphaDecay below was set back to settle in a few seconds rather
        /// than ~15: at the faster decay, disconnected clusters have fewer ticks to physically
        /// separate before the simulation freezes, and more retained momentum (less friction)
        /// is what buys that separation back within the same tick budget -- confirmed against
        /// the clustering test's fixture, not just by reasoning about it.
        static let damping: Double = 0.75

        /// Alpha ("temperature") starts at 1 and decays geometrically each tick; every force
        /// this tick is scaled by the alpha value in effect *before* that tick's decay, so the
        /// assembly visibly cools rather than stopping abruptly. 0.02 settles in ~263 ticks,
        /// about 4.4s at 60fps, matching PLAN.md's "settles over several seconds".
        static let alphaDecay: Double = 0.02

        /// Once alpha decays to this floor, `isSettled` becomes true and further `tick()`
        /// calls are a no-op: "settled" means positions are frozen bit-for-bit, not merely
        /// asymptotically close, which is what the renderer's rest-state and this file's own
        /// determinism tests both rely on.
        static let alphaFloor: Double = 0.005

        /// Defensive clamp on a single tick's velocity magnitude. Repulsion is O(1/distance),
        /// so a pathological configuration (many nodes forced to near-identical starting
        /// points) could otherwise eject a node a very long way in one step before the rest
        /// of the system has had a chance to spread out.
        static let maxVelocityPerTick: Double = 40

        /// Below this distance, two nodes are treated as coincident: the direction used for
        /// repulsion/spring force falls back to a deterministic offset (see `separationOffset`)
        /// instead of dividing by a (near) zero distance.
        static let minDistance: Double = 0.5

        static let minRadius: CGFloat = 4
        static let maxRadius: CGFloat = 28
        static let userRadius: CGFloat = 14
        static let radiusScale: CGFloat = 3.2

        /// Initial ring nodes are scattered on, as a fraction of min(size.width, size.height).
        static let ringFractionMin: Double = 0.15
        static let ringFractionMax: Double = 0.45
    }

    private struct NodeState {
        let id: String
        let isPinned: Bool
        var position: CGPoint
        /// Reused loosely as a 2D vector (dx, dy), not a point; kept private so the public
        /// surface never has to explain that abuse.
        var velocity: CGPoint = .zero
    }

    private struct Spring {
        let a: Int
        let b: Int
        /// sqrt(strength + 1): sqrt so a 300-day thread does not become a rigid rod against
        /// a 2-day one (linear strength would make the stiffness ratio 150x; sqrt brings it
        /// to about 12x). The +1 keeps a zero-activity lurker's membership edge spring-connected
        /// to their group at all -- they are still structurally part of the roster.
        let scaledStrength: Double
    }

    private var nodeStates: [NodeState]
    private let indexByID: [String: Int]
    private let springs: [Spring]
    private let center: CGPoint

    public private(set) var alpha: Double = 1.0
    public private(set) var isSettled: Bool = false

    /// Static per node: degree does not change during the simulation, and this is computed
    /// once at init rather than re-derived from the (possibly pruned-differently) spring set.
    /// Uses the Graph's own stored `degree` -- the whole-graph connection count, including
    /// edges to the user and to dead groups -- per PLAN.md "node size scales with connection
    /// count", not the narrower visible/spring-participating subset used by the physics.
    public let radii: [String: CGFloat]

    /// Visible node ids in the fixed order the simulation iterates internally (sorted by id
    /// at init). Exposed so the renderer can iterate deterministically without re-sorting
    /// `positions`' keys every frame.
    public var orderedNodeIDs: [String] {
        nodeStates.map(\.id)
    }

    public var positions: [String: CGPoint] {
        Dictionary(uniqueKeysWithValues: nodeStates.map { ($0.id, $0.position) })
    }

    public convenience init(graph: Graph, size: CGSize, includeDeadGroups: Bool = false) {
        self.init(graph: graph, size: size, includeDeadGroups: includeDeadGroups, positionOverrides: [:])
    }

    /// Test seam: force exact starting positions for named ids (e.g. a deterministic
    /// zero-distance collision) instead of hunting for a natural hash collision.
    internal init(graph: Graph, size: CGSize, includeDeadGroups: Bool = false, positionOverrides: [String: CGPoint]) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        self.center = center

        // Visible set: user + person nodes + LIVE group nodes, plus dead groups too when the
        // dead-groups toggle (AppModel.DisplayOptions.showDeadGroups) is on. A dead group's
        // edges are automatically excluded below since both endpoints of an edge must be
        // visible -- unchanged when includeDeadGroups is false, which is still the default.
        let visibleNodes = graph.nodes
            .filter { $0.kind != .group || $0.isLive || includeDeadGroups }
            .sorted { $0.id < $1.id }

        var states: [NodeState] = []
        states.reserveCapacity(visibleNodes.count)
        var indices: [String: Int] = [:]
        var radiiBuilder: [String: CGFloat] = [:]

        for node in visibleNodes {
            let isUser = node.kind == .user
            let position: CGPoint
            if isUser {
                position = center
            } else if let override = positionOverrides[node.id] {
                position = override
            } else {
                position = Self.initialPosition(for: node.id, center: center, size: size)
            }
            indices[node.id] = states.count
            states.append(NodeState(id: node.id, isPinned: isUser, position: position))
            radiiBuilder[node.id] = Self.suggestedRadius(kind: node.kind, degree: node.degree)
        }

        self.nodeStates = states
        self.indexByID = indices
        self.radii = radiiBuilder

        // Springs: only edges between two visible nodes with involvesUser == false. By
        // construction every user-touching edge has involvesUser == true, so this already
        // excludes anything touching the pinned user node; the visibility lookup below is
        // what actually drops edges into/out of dead groups.
        var builtSprings: [Spring] = []
        for edge in graph.edges.sorted(by: { $0.id < $1.id }) {
            guard !edge.involvesUser else { continue }
            guard let a = indices[edge.nodeIDA], let b = indices[edge.nodeIDB] else { continue }
            builtSprings.append(Spring(a: a, b: b, scaledStrength: (edge.strength + 1.0).squareRoot()))
        }
        self.springs = builtSprings
    }

    public func tick() {
        guard !isSettled else { return }

        let count = nodeStates.count
        var forceX = [Double](repeating: 0, count: count)
        var forceY = [Double](repeating: 0, count: count)

        // Pairwise repulsion, visible non-user nodes only. O(n^2); fine at hundreds of nodes.
        if count > 1 {
            for i in 0..<(count - 1) {
                guard !nodeStates[i].isPinned else { continue }
                for j in (i + 1)..<count {
                    guard !nodeStates[j].isPinned else { continue }
                    let (dx, dy, distSq) = separation(i, j)
                    let dist = distSq.squareRoot()
                    let magnitude = Tuning.repulsionConstant / distSq
                    let fx = (dx / dist) * magnitude
                    let fy = (dy / dist) * magnitude
                    forceX[i] += fx
                    forceY[i] += fy
                    forceX[j] -= fx
                    forceY[j] -= fy
                }
            }
        }

        // Springs: Hooke's law toward restLength, scaled by the edge's sqrt-scaled strength.
        for spring in springs {
            guard !nodeStates[spring.a].isPinned, !nodeStates[spring.b].isPinned else { continue }
            let (dx, dy, distSq) = separation(spring.a, spring.b)
            let dist = distSq.squareRoot()
            let displacement = dist - Tuning.restLength
            let magnitude = Tuning.springConstant * spring.scaledStrength * displacement
            // separation(a, b) returns dx/dy pointing from b to a; a positive (too-far)
            // displacement must pull a toward b, i.e. in the opposite direction, hence the
            // negation. (Getting this sign wrong turns the restoring spring into a positive
            // feedback loop -- caught by comparing against a scratch print of real positions,
            // not by inspection: the earlier signed version compiled and ran, it just diverged.)
            let fx = -(dx / dist) * magnitude
            let fy = -(dy / dist) * magnitude
            forceX[spring.a] += fx
            forceY[spring.a] += fy
            forceX[spring.b] -= fx
            forceY[spring.b] -= fy
        }

        // Weak centering: a spring to the fixed center point, rest length zero.
        for i in 0..<count where !nodeStates[i].isPinned {
            let dx = center.x - nodeStates[i].position.x
            let dy = center.y - nodeStates[i].position.y
            forceX[i] += Double(dx) * Tuning.centeringStrength
            forceY[i] += Double(dy) * Tuning.centeringStrength
        }

        // Integrate: velocity damping, clamp, then position update, all scaled by this tick's
        // alpha (the value in effect before decay below).
        for i in 0..<count where !nodeStates[i].isPinned {
            var vx = (Double(nodeStates[i].velocity.x) + forceX[i] * alpha) * Tuning.damping
            var vy = (Double(nodeStates[i].velocity.y) + forceY[i] * alpha) * Tuning.damping
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed > Tuning.maxVelocityPerTick {
                let scale = Tuning.maxVelocityPerTick / speed
                vx *= scale
                vy *= scale
            }
            nodeStates[i].velocity = CGPoint(x: vx, y: vy)
            nodeStates[i].position.x += CGFloat(vx)
            nodeStates[i].position.y += CGFloat(vy)
        }

        alpha = max(alpha * (1.0 - Tuning.alphaDecay), 0.0)
        if alpha <= Tuning.alphaFloor {
            isSettled = true
        }
    }

    public func radius(for id: String) -> CGFloat? {
        radii[id]
    }

    /// Displacement and squared distance between two node indices, with a deterministic
    /// fallback direction when the nodes are at (or extremely near) the same position: real
    /// coincidences happen (two nodes can hash to the same initial ring position, or a chain
    /// of ticks can drive two nodes together), and dividing by ~zero distance must never
    /// happen, but the fallback must still be reproducible, not arbitrary.
    private func separation(_ i: Int, _ j: Int) -> (dx: Double, dy: Double, distSq: Double) {
        var dx = Double(nodeStates[i].position.x - nodeStates[j].position.x)
        var dy = Double(nodeStates[i].position.y - nodeStates[j].position.y)
        var distSq = dx * dx + dy * dy
        let minDistSq = Tuning.minDistance * Tuning.minDistance
        if distSq < minDistSq {
            let offset = Self.separationOffset(idA: nodeStates[i].id, idB: nodeStates[j].id)
            dx = offset.dx
            dy = offset.dy
            distSq = dx * dx + dy * dy
        }
        return (dx, dy, distSq)
    }

    private static func separationOffset(idA: String, idB: String) -> (dx: Double, dy: Double) {
        let orderedKey = idA <= idB ? "\(idA)|\(idB)" : "\(idB)|\(idA)"
        let hash = fnv1a(orderedKey)
        let angle = 2.0 * Double.pi * Double(hash % 3600) / 3600.0
        return (cos(angle) * Tuning.minDistance, sin(angle) * Tuning.minDistance)
    }

    private static func initialPosition(for id: String, center: CGPoint, size: CGSize) -> CGPoint {
        let angle = 2.0 * Double.pi * Double(fnv1a(id) % 3600) / 3600.0
        let radiusFraction = Tuning.ringFractionMin
            + (Double(fnv1a(id + "|r") % 1000) / 1000.0) * (Tuning.ringFractionMax - Tuning.ringFractionMin)
        let ringRadius = radiusFraction * Double(min(size.width, size.height))
        return CGPoint(
            x: center.x + CGFloat(ringRadius * cos(angle)),
            y: center.y + CGFloat(ringRadius * sin(angle))
        )
    }

    private static func suggestedRadius(kind: NodeKind, degree: Int) -> CGFloat {
        guard kind != .user else { return Tuning.userRadius }
        let base = CGFloat(Double(max(degree, 0)).squareRoot()) * Tuning.radiusScale
        return min(max(base, Tuning.minRadius), Tuning.maxRadius)
    }

    /// FNV-1a, 64-bit. Deterministic and unseeded, unlike `Hasher`/`String.hashValue`, which
    /// are randomized per process specifically to resist hash-flooding attacks -- exactly the
    /// property that would make "same graph, same assembly" false across two runs.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
