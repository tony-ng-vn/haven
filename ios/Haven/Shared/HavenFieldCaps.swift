import Foundation

/// How long a free-text card field may be.
///
/// A port of `convex/fieldCaps.ts`, and it has to stay one. The server throws
/// for a value over these lengths, and the two paths that reach it do not fail
/// alike: an editor can say "shorten this" and be shortened, while a queued
/// capture is replayed by the drain long after the sheet closed, with nobody
/// there to tell. So the queue's own writer refuses over-long values up front
/// rather than filing one that can never drain and retries for the life of the
/// install.
///
/// Foundation only: this is compiled into the share extension.
enum HavenFieldCaps {
    /// The prototype's number, and the card's name line is drawn for it.
    static let name = 40
    /// A city name, and its admin area and country, each rendered beside it.
    static let cityPart = 40
    /// Company and role, one rendered line each.
    static let line = 60
    /// Long enough for the longest LinkedIn slug worth storing and an
    /// international number with spaces.
    static let handle = 60

    /// What a field says when there is too much in it.
    ///
    /// Names the field and the number, the way the server's own message does,
    /// because "too long" without a number is a guessing game. Said in the
    /// editor rather than after a round trip: the server throws for these, and
    /// a throw here would surface as "check your connection", which is a lie
    /// about a problem the person can see and fix.
    static func tooLong(_ label: String, max: Int) -> String {
        "Keep \(label) under \(max) characters."
    }

    /// Counted in code points, not UTF-16 units, exactly as the server counts:
    /// the cap exists so a value fits a line, and one emoji or one composed
    /// Vietnamese vowel is one thing on that line rather than two.
    static func fits(_ value: String, within max: Int) -> Bool {
        value.unicodeScalars.count <= max
    }
}
