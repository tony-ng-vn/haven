import XCTest
@testable import GraphCore

final class RelaunchTests: XCTestCase {
    func testCommandUsesOpenWithDashNAndTheGivenBundlePath() {
        let command = Relaunch.command(forBundlePath: "/Applications/Your Sky.app")

        XCTAssertEqual(command.executablePath, "/usr/bin/open")
        XCTAssertEqual(command.arguments, ["-n", "/Applications/Your Sky.app"])
    }

    func testCommandPreservesAnArbitraryBundlePathVerbatim() {
        // A DerivedData/ad-hoc build path, not /Applications -- the whole point of showing
        // this path on screen is that the running copy might NOT be the canonical install.
        let path = "/Users/example/Library/Developer/Xcode/DerivedData/ConnectionGraph-abc"
            + "/Build/Products/Release/Your Sky.app"
        let command = Relaunch.command(forBundlePath: path)

        XCTAssertEqual(command.arguments, ["-n", path])
    }
}
