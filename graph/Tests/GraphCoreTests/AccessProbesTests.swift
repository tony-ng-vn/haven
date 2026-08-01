import XCTest
@testable import GraphCore

final class MessagesAccessProbeTests: XCTestCase {
    func testGrantedWhenChatDBOpens() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }
        XCTAssertTrue(MessagesAccessProbe.check(path: fixture.url.path))
    }

    func testBlockedWhenPathDoesNotExist() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-chat-\(UUID().uuidString).db").path
        XCTAssertFalse(MessagesAccessProbe.check(path: missingPath))
    }
}

final class ContactsAccessProbeTests: XCTestCase {
    func testNoDataWhenNoPathsDiscovered() {
        XCTAssertEqual(ContactsAccessProbe.check(paths: []), .noData)
    }

    func testGrantedWhenAtLeastOnePathOpens() throws {
        let fixture = try ContactsDBFixture()
        defer { fixture.close() }
        XCTAssertEqual(ContactsAccessProbe.check(paths: [fixture.url.path]), .granted)
    }

    func testBlockedWhenPathsExistButNoneOpen() {
        // A path FileManager reports as present but sqlite3_open_v2 cannot actually open
        // (the real-world shape of "found the file, TCC denied the read") -- simulated
        // here with a path to a directory, which sqlite3_open_v2 always refuses.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("contacts-blocked-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(ContactsAccessProbe.check(paths: [dir.path]), .blocked)
    }
}

final class ContactsPathDiscoveryTests: XCTestCase {
    private func makeHome() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("contacts-discovery-\(UUID().uuidString)", isDirectory: true)
    }

    func testNoAddressBookDirectoryYieldsEmptyNotError() {
        let home = makeHome()
        XCTAssertEqual(ContactsPathDiscovery.discoverPaths(home: home.path), [])
    }

    func testFindsTopLevelAndLinkedSourceDatabases() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        let root = home.appendingPathComponent("Library/Application Support/AddressBook")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("AddressBook-v22.abcddb"))

        let sourceDir = root.appendingPathComponent("Sources/ABCDEF")
        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data().write(to: sourceDir.appendingPathComponent("AddressBook-v22.abcddb"))

        let paths = ContactsPathDiscovery.discoverPaths(home: home.path)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.contains(root.appendingPathComponent("AddressBook-v22.abcddb").path))
        XCTAssertTrue(paths.contains(sourceDir.appendingPathComponent("AddressBook-v22.abcddb").path))
    }
}
