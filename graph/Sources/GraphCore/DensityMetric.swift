import Foundation

/// The density figure PLAN.md's calibration target (1.19, against a 1.04 reference) actually
/// counted: one-to-one thread edges plus group membership edges, over person nodes plus LIVE
/// group nodes. Deliberately excludes userGroupMembership edges from the numerator and dead
/// groups from the denominator -- the CLI's older `edgesPerNode` line mixed those in under a
/// different definition and is not comparable to the plan's number (see journal iteration 4).
public enum DensityMetric {
    public static func planComparable(graph: Graph) -> Double {
        let numerator = graph.edges.filter { $0.reason == .oneToOneThread || $0.reason == .groupMembership }.count
        let personNodes = graph.nodes.filter { $0.kind == .person }.count
        let liveGroupNodes = graph.nodes.filter { $0.kind == .group && $0.isLive }.count
        let denominator = personNodes + liveGroupNodes
        return denominator > 0 ? Double(numerator) / Double(denominator) : 0.0
    }
}
