import Foundation

/// What a Haven address may be.
///
/// A port of `normalizeUsername` and `HANDLE_PATTERN` in `convex/profiles.ts`
/// and `convex/handleNames.ts`, and it has to stay one. It is here so the
/// address editor can say what will be claimed before it claims it, and refuse
/// a shape the server would refuse anyway -- a round trip to be told "that is
/// not an address" is a round trip nobody needed.
///
/// It deliberately does not carry the reserved list. Whether a name belongs to
/// the site is the server's call and it answers `taken` for one, with
/// suggestions; duplicating the list here would mean two places to keep in step
/// and a client that refuses names the server would have offered a way around.
enum HavenHandle {
    /// The lowest and highest a handle can be. `HANDLE_PATTERN` is
    /// `^[a-z0-9_]{3,24}$`.
    static let minimumLength = 3
    static let maximumLength = 24

    /// What the server would store for this text. Trims, drops leading `@`, and
    /// lower-cases, exactly as `normalizeUsername` does.
    static func normalize(_ raw: String) -> String {
        var value = raw.trimmedLikeJS
        while value.hasPrefix("@") { value.removeFirst() }
        return value.lowercased()
    }

    /// Whether this is a shape a handle can take. Says nothing about whether
    /// anybody holds it.
    static func isWellFormed(_ handle: String) -> Bool {
        guard handle.count >= minimumLength, handle.count <= maximumLength else {
            return false
        }
        return handle.allSatisfy(allowed.contains)
    }

    /// The address this text would claim, or nil while there is not a usable
    /// one -- which is what holds Save disabled.
    static func candidate(from raw: String) -> String? {
        let normalized = normalize(raw)
        return isWellFormed(normalized) ? normalized : nil
    }

    /// What to say when the text is not an address yet.
    ///
    /// One sentence rather than a live rule-by-rule critique: somebody halfway
    /// through typing has not made a mistake, and a field that scolds every
    /// keystroke is worse than one that waits.
    static let help = "Three to twenty-four characters: letters, numbers and underscores."

    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
}
