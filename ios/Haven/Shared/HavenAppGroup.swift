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

    /// Where the app keeps the same files when the group is not provisioned.
    ///
    /// Private to the app, so the extension can never read it -- which is why
    /// only the app has a use for it. It exists because saving somebody by hand
    /// writes to the queue first and must never fail, and on a device missing
    /// the group entitlement `containerURL` is nil.
    static var appContainerURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Haven", isDirectory: true)
    }
}
