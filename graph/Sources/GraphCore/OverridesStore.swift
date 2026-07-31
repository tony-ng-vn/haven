import Foundation

/// Loads/saves the user's Overrides as JSON at an injectable file URL. The designated init
/// takes a required URL rather than defaulting to the real on-disk location, so a test can
/// never reach the user's actual Application Support folder by accident -- only AppModel's
/// own call site uses `defaultFileURL()`.
public struct OverridesStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// ~/Library/Application Support/ConnectionGraph/overrides.json. Deliberately a separate
    /// static function, not a default parameter value on init, so it is never the accidental
    /// default in a test that forgets to pass a temp-dir URL.
    public static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("ConnectionGraph", isDirectory: true)
            .appendingPathComponent("overrides.json", isDirectory: false)
    }

    /// A missing file means a fresh install or a resync before the first save: empty
    /// overrides, not an error. A file that exists but fails to decode DOES throw -- silently
    /// resetting to empty there would erase real user curation, which is exactly the failure
    /// PLAN.md's "user curation survives resync" rules out. The caller (AppModel) maps that
    /// throw to its own failed state.
    public func load() throws -> Overrides {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Overrides()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Overrides.self, from: data)
    }

    /// Creates the containing directory on first save (nothing to create on every later
    /// save: withIntermediateDirectories is a no-op once it already exists). Atomic write so
    /// a crash mid-write can never leave a half-written file for the next load() to trip on.
    public func save(_ overrides: Overrides) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(overrides)
        try data.write(to: fileURL, options: .atomic)
    }
}
