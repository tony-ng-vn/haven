import Foundation

/// "v1.0.0 - built Aug 4, 4:41 PM": which build this is, not just which
/// version.
///
/// Debug-only, and shown nowhere a real user ever sees it (see
/// `DirectoryScreen`'s `#if DEBUG` around the one place this is read): two
/// installs of the same version number, one just freshly rebuilt over the
/// simulator, read identically without a build time on them, and the version
/// alone is exactly the number that does not change between them.
enum DevBuildLabel {
    /// Nil rather than a partial line if either half is missing: a caption
    /// showing only a version restates what Settings already says, and one
    /// showing only a time with no "v" in front of it reads as a bug rather
    /// than a deliberate build tag.
    ///
    /// `timeZone` defaults to the device's own, which is what makes the time
    /// mean anything to whoever is looking at their own phone; it is a
    /// parameter, not a hardcoded `.current`, only so a test can pin it and
    /// not depend on the machine that happens to run the suite.
    static func caption(
        version: String?,
        builtAt: Date?,
        timeZone: TimeZone = .current
    ) -> String? {
        guard let version, !version.isEmpty, let builtAt else { return nil }
        return "v\(version) - built \(Self.formatter(timeZone: timeZone).string(from: builtAt))"
    }

    /// A fixed "MMM d, h:mm a" rather than a localized style on purpose: this
    /// line is read by whoever is holding the phone that just built it, not
    /// by an end user, and a consistent shape across every developer's own
    /// device locale beats one that reorders itself per region for a caption
    /// nobody but the team ever sees.
    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }
}

/// Where `DevBuildLabel.caption` gets its two inputs. Kept apart from the
/// formatting above on purpose: this is the one part of the pair that cannot
/// be unit tested (it reads the bundle and the filesystem this process
/// actually launched from), so it stays a thin shim with nothing in it worth
/// asserting on beyond "the app builds and runs".
enum DevBuildInfo {
    /// `CFBundleShortVersionString`, straight from the bundle Xcode wrote --
    /// the same number Settings shows, never hand-maintained here.
    static var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// The executable's own file modification date: zero-maintenance and
    /// truthful in a way a hand-written string could never be, because it is
    /// not this file saying when the build happened, it is the build saying
    /// it about itself. Xcode recompiles and relinks the binary on every
    /// build that changes anything, so its mtime is the moment linking
    /// finished -- not the moment the app happened to launch, and not the
    /// project file's own timestamp, which changes on every `xcodegen
    /// generate` whether or not any code did.
    static var builtAt: Date? {
        guard let url = Bundle.main.executableURL else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}
