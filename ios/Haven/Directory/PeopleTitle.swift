import Foundation

/// The People screen's title: whoever is signed in, not a count of who they
/// saved.
///
/// A name reads warmer than an inventory, and the count this replaced had
/// already stopped being useful for anyone with more people than one page
/// holds -- see `DirectoryModel`'s now-removed `countIsPartial`, which said
/// "50+" forever to someone with three hundred.
enum PeopleTitle {
    /// "Tony's Haven", or "Your Haven" before a name is known.
    ///
    /// The possessive is simple on purpose: the first name as typed, plus
    /// "'s", with no attempt to special-case a name that already ends in
    /// "s" ("Chris" becomes "Chris's", not "Chris'"). Haven did not choose
    /// the name and has no house style to apply to it beyond the one rule
    /// every name gets.
    static func title(firstName: String?) -> String {
        guard let first = firstName?.trimmed, !first.isEmpty else { return "Your Haven" }
        return "\(first)'s Haven"
    }

    /// The first word of a full name, or nil if there is nothing to take one
    /// from. "First" rather than "given": Haven never asked which name goes
    /// where, only for the one field a person filled in themselves.
    static func firstName(of name: String?) -> String? {
        guard let name else { return nil }
        let first = name.trimmed.split(separator: " ", maxSplits: 1).first
        return first.map(String.init)
    }
}
