import Foundation

/// Whether a saved handle is old enough to be worth a second look.
///
/// Used for LinkedIn in `PersonScreen`, not because the logic is
/// LinkedIn-specific, but because LinkedIn is the one platform Haven cannot
/// refresh on its own: unlike Instagram and X (`PersonReach.openURL`), there
/// is no numeric id and no rename-proof link, so a stale slug can silently
/// point at somebody else's profile after they change their name.
enum HandleStaleness {
    /// The web uses the same fixed 180-day policy. Keeping this duration
    /// identical prevents the two clients disagreeing near month boundaries.
    private static let staleAfter: TimeInterval = 60 * 60 * 24 * 180

    /// Nil `addedAt` means a row saved before the field existed, and that is
    /// silence rather than staleness -- there is nothing to compare against,
    /// and guessing an age would be worse than saying nothing.
    ///
    static func isStale(
        addedAt: Double?,
        comparedTo now: Date = Date()
    ) -> Bool {
        guard let addedAt else { return false }
        let added = Date(timeIntervalSince1970: addedAt / 1000)
        return now.timeIntervalSince(added) > staleAfter
    }
}
