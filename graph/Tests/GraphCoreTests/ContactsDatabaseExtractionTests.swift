import XCTest
@testable import GraphCore

final class ContactsDatabaseExtractionTests: XCTestCase {

    // Test 11: first+last+phone, email-only, and organization-only all extract with the
    // right phones/emails attached via ZOWNER; a fully empty record is excluded.
    func testMixedRecordShapesExtractCorrectly() throws {
        let fixture = try ContactsDBFixture()
        defer { fixture.close() }

        try fixture.insertRecord(recordID: 1, firstName: "Jane", lastName: "Doe")
        try fixture.insertPhoneNumber(recordID: 10, ownerID: 1, fullNumber: "+15551230000")

        try fixture.insertRecord(recordID: 2)
        try fixture.insertEmailAddress(recordID: 20, ownerID: 2, address: "person@example.com")

        try fixture.insertRecord(recordID: 3, organization: "Acme Corp")

        // Fully empty record: no name, no organization, no phone, no email.
        try fixture.insertRecord(recordID: 4)

        fixture.close()

        let records = try ContactsDatabase.extract(path: fixture.url.path)
        XCTAssertEqual(records.count, 3)
        XCTAssertFalse(records.contains { $0.recordID == 4 })

        let janeDoe = try XCTUnwrap(records.first { $0.recordID == 1 })
        XCTAssertEqual(janeDoe.firstName, "Jane")
        XCTAssertEqual(janeDoe.lastName, "Doe")
        XCTAssertEqual(janeDoe.phoneNumbers, ["+15551230000"])
        XCTAssertTrue(janeDoe.emails.isEmpty)

        let emailOnly = try XCTUnwrap(records.first { $0.recordID == 2 })
        XCTAssertNil(emailOnly.firstName)
        XCTAssertNil(emailOnly.lastName)
        XCTAssertNil(emailOnly.organization)
        XCTAssertEqual(emailOnly.emails, ["person@example.com"])
        XCTAssertTrue(emailOnly.phoneNumbers.isEmpty)

        let organizationOnly = try XCTUnwrap(records.first { $0.recordID == 3 })
        XCTAssertEqual(organizationOnly.organization, "Acme Corp")
        XCTAssertNil(organizationOnly.firstName)
        XCTAssertTrue(organizationOnly.phoneNumbers.isEmpty)
        XCTAssertTrue(organizationOnly.emails.isEmpty)
    }
}
