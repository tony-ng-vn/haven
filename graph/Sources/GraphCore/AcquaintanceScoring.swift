import Foundation

/// The acquaintance layer's scoring constants (PLAN.md), named once so the numbers have exactly
/// one place to change: they are calibrated guesses in the P3 sense (measure against the real
/// graph, journal the numbers, tune), not settled forever.
public enum AcquaintanceScoring {
    /// Score at or above this is tier `strong`.
    public static let strongThreshold: Double = 1.0
    /// Score at or above this (and below strongThreshold) is tier `likely`. Below this, no
    /// acquaintance edge is recorded at all.
    public static let likelyThreshold: Double = 0.2
    /// Added to a pair's score per day both people were active in a shared chat.
    public static let coActiveDayWeight: Double = 0.1
    /// coActiveDayWeight stops accruing past this many days in a single chat: PLAN.md's
    /// example is 6 shared days contributing +0.5, not +0.6.
    public static let coActiveDayCapPerChat: Int = 5
}
