import Foundation

/// The container the app and the share extension both reach.
///
/// The extension does no network at all: it writes captures here and reads the
/// directory mirror the app leaves here, and the app drains the queue into
/// Convex on next launch. That is what lets a capture made in airplane mode,
/// or before anyone has signed in, still land.
///
/// note: the entitlement alone does not provision this. The group has to exist
/// in the developer portal and be on both App IDs, or `containerURL` answers
/// nil on a real device while the simulator carries on working.
enum HavenAppGroup {
    static let identifier = "group.com.inhavens.haven"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )
    }
}
