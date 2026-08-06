import Foundation

/// Whether a saved handle is old enough to be worth a second look.
///
/// Used for LinkedIn in `PersonScreen`, not because the logic is
/// LinkedIn-specific, but because LinkedIn is the one platform Haven cannot
/// refresh on its own: unlike Instagram and X (`PersonReach.openURL`), there
/// is no numeric id and no rename-proof link, so a stale slug can silently
/// point at somebody else's profile after they change their name.
enum HandleStaleness {
    /// Six months, not thirty days: a link is right until proven otherwise,
    /// and a hint that fires every month reads as nagging rather than useful.
    private static let staleAfterMonths = 6
    private static let gregorian = Calendar(identifier: .gregorian)

    /// Nil `addedAt` means a row saved before the field existed, and that is
    /// silence rather than staleness -- there is nothing to compare against,
    /// and guessing an age would be worse than saying nothing.
    ///
    /// `calendar` defaults to Gregorian explicitly rather than `.current`:
    /// "six months" is meant as a fixed span regardless of the device's own
    /// calendar identifier, and injectable for a deterministic test either way.
    static func isStale(
        addedAt: Double?,
        comparedTo now: Date = Date(),
        calendar: Calendar = gregorian
    ) -> Bool {
        guard let addedAt else { return false }
        let added = Date(timeIntervalSince1970: addedAt / 1000)
        guard
            let staleAfter = calendar.date(byAdding: .month, value: staleAfterMonths, to: added)
        else { return false }
        return now > staleAfter
    }
}
