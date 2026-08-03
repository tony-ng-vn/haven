import XCTest
@testable import GraphCore

final class MessageTextNeverCarriedTests: XCTestCase {

    // Test 9: insert a distinctive sentinel into message.text and attributedBody, extract,
    // then recursively walk every String reachable from ChatExtract and assert it is absent.
    // A positive control (a legitimate string that really is in the model) proves the walker
    // is not vacuously passing by never reaching anything.
    func testSentinelMessageTextNeverReachesTheWorkingModel() throws {
        let fixture = try ChatDBFixture()
        defer { fixture.close() }

        let sentinelText = "SENTINEL-TEXT-9f3ac2-do-not-extract"
        let sentinelBlob = "SENTINEL-BLOB-71bd8e-do-not-extract"
        let legitimateGuid = "legit-guid-should-be-found-42"

        try fixture.insertHandle(rowID: 1, id: "+15550009999", service: "iMessage")
        try fixture.insertChat(
            rowID: 1,
            guid: legitimateGuid,
            style: 45,
            chatIdentifier: "+15550009999"
        )
        try fixture.insertChatHandleJoin(chatID: 1, handleID: 1)
        try fixture.insertMessage(
            rowID: 1,
            text: sentinelText,
            attributedBody: Data(sentinelBlob.utf8),
            handleID: 1,
            service: "iMessage",
            dateNanoseconds: 700_000_000_000_000_000,
            isFromMe: false
        )
        try fixture.insertChatMessageJoin(chatID: 1, messageID: 1)
        fixture.close()

        let extract = try ChatDatabase.extract(path: fixture.url.path)
        let strings = allStrings(reachableFrom: extract)

        XCTAssertFalse(strings.contains(sentinelText), "message.text leaked into the working model")
        XCTAssertFalse(strings.contains(sentinelBlob), "attributedBody content leaked into the working model")
        XCTAssertFalse(
            strings.contains { $0.contains("do-not-extract") },
            "some fragment of the sentinel leaked into the working model"
        )
        XCTAssertTrue(
            strings.contains(legitimateGuid),
            "positive control failed: the walker never reached a string that legitimately lives in the model, so the assertions above prove nothing"
        )
    }

    // Recursively collects every String value reachable through Mirror reflection,
    // descending into optionals (one child when non-nil) and collections (children are elements).
    private func allStrings(reachableFrom value: Any) -> [String] {
        var found: [String] = []
        func walk(_ any: Any) {
            if let string = any as? String {
                found.append(string)
                return
            }
            let mirror = Mirror(reflecting: any)
            if mirror.displayStyle == .optional {
                if let child = mirror.children.first {
                    walk(child.value)
                }
                return
            }
            for child in mirror.children {
                walk(child.value)
            }
        }
        walk(value)
        return found
    }
}
