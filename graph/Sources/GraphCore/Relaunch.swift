import Foundation

/// The exact process-spawn shape for restarting this app: `/usr/bin/open -n <bundlePath>`.
/// A pure value, not a live Process invocation -- the actual spawn-and-terminate sequence
/// (AppModel.relaunch) needs AppKit (NSApplication.terminate) and a real Process, neither
/// meaningfully testable without a running app, so this is the one piece of that flow that
/// IS unit tested, and the AppKit-dependent remainder stays a thin wrapper around it.
public struct RelaunchCommand: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public enum Relaunch {
    /// `-n`: forces a new instance rather than reactivating the one already running (`man
    /// open`) -- load-bearing here, since the calling process is still alive at the moment
    /// this command runs, which is exactly the case `-n` exists for.
    public static func command(forBundlePath bundlePath: String) -> RelaunchCommand {
        RelaunchCommand(executablePath: "/usr/bin/open", arguments: ["-n", bundlePath])
    }
}
