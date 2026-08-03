import XCTest
@testable import GraphCore

final class DevToolAvailabilityTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-tool-availability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // The regression this exists to catch: a compile-time-baked repo path (AppModel.repoRoot,
    // built from #filePath) pointing at a worktree that has since been deleted.
    func testUnavailableWhenTheCandidateRootItselfDoesNotExist() {
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-root-\(UUID().uuidString)")
        XCTAssertFalse(DevToolAvailability.syncScriptExists(atRepoRoot: missingRoot.path))
    }

    func testUnavailableWhenRootExistsButHasNoScriptsDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(DevToolAvailability.syncScriptExists(atRepoRoot: root.path))
    }

    func testAvailableWhenScriptsSyncPolygresExistsUnderTheRoot() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptsDir = root.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try Data().write(to: scriptsDir.appendingPathComponent("sync_polygres.py"))

        XCTAssertTrue(DevToolAvailability.syncScriptExists(atRepoRoot: root.path))
    }
}
