import Foundation

/// Whether a development-only utility can actually run right now, given the on-disk repo
/// path it depends on. GOAL.md rules out a production surface for this app, and Sync people
/// (scripts/sync_polygres.py) is exactly that: a tool for the checkout that built this
/// binary, not a shipped feature.
///
/// AppModel.repoRoot is baked in at compile time from `#filePath`, so it is only ever true
/// for the checkout that happened to compile the running binary. A worktree can be deleted
/// long after the binary keeps running -- an installed `/Applications` copy in particular
/// outlives any single worktree -- so the compiled-in path is not something to trust without
/// re-checking. The correct behavior for a stale path is the affordance simply not
/// appearing, never a runtime error surfaced to the user.
public enum DevToolAvailability {
    /// True only when `scripts/sync_polygres.py` actually exists under `repoRootPath` RIGHT
    /// NOW. Checked against the filesystem on every call, never cached from build or launch
    /// time: a worktree deleted while the app is already running must hide the feature just
    /// as surely as one deleted before the app ever launched.
    public static func syncScriptExists(atRepoRoot repoRootPath: String, fileManager: FileManager = .default) -> Bool {
        let scriptPath = (repoRootPath as NSString).appendingPathComponent("scripts/sync_polygres.py")
        return fileManager.fileExists(atPath: scriptPath)
    }
}
