import XCTest
@testable import GraphCore

final class ContactOnlyPeopleTests: XCTestCase {

    private func contactRecord(
        recordID: Int64,
        uniqueID: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        organization: String? = nil,
        nickname: String? = nil,
        phoneNumbers: [String] = [],
        emails: [String] = [],
        thumbnailImageData: Data? = nil
    ) -> ContactRecord {
        ContactRecord(
            recordID: recordID,
            uniqueID: uniqueID ?? "uid-\(recordID)",
            firstName: firstName,
            lastName: lastName,
            organization: organization,
            nickname: nickname,
            phoneNumbers: phoneNumbers,
            emails: emails,
            thumbnailImageData: thumbnailImageData
        )
    }

    // MARK: - The correctness crux (brief requirement 5)

    // A card with several numbers where only one has message evidence must resolve to the
    // SAME person -- never a new contact-only node.
    func testCardWithSeveralNumbersOneMatchingResolvesToExistingPersonNotANewNode() {
        let contacts = [
            contactRecord(
                recordID: 1,
                firstName: "Ana",
                lastName: "Vray",
                phoneNumbers: ["+14155550001", "+14155550002", "+14155550003"]
            )
        ]
        // Only the middle number ever appeared as a message handle.
        let matched: Set<String> = ["+14155550002"]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: matched)

        XCTAssertTrue(result.people.isEmpty)
        XCTAssertEqual(result.excluded, [ExcludedContactCard(contactCardID: "uid-1", reason: .matchesExistingPerson)])
    }

    // A card whose identifiers share nothing with any message handle becomes a new node.
    func testCardWithNoMatchingIdentifierBecomesContactOnlyNode() {
        let contacts = [
            contactRecord(recordID: 2, firstName: "Bo", lastName: "Marrow", phoneNumbers: ["+14155550010"])
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertEqual(result.people.count, 1)
        XCTAssertEqual(result.people.first?.id, "+14155550010")
        XCTAssertEqual(result.people.first?.name, "Bo Marrow")
        XCTAssertEqual(result.people.first?.contactCardID, "uid-2")
        XCTAssertTrue(result.excluded.isEmpty)
    }

    // MARK: - Non-person exclusion (brief requirement 6)

    func testOrganizationOnlyCardIsExcludedAsNonPerson() {
        let contacts = [
            contactRecord(recordID: 3, organization: "Acme Cable Co", phoneNumbers: ["+14155550020"])
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertTrue(result.people.isEmpty)
        XCTAssertEqual(result.excluded, [ExcludedContactCard(contactCardID: "uid-3", reason: .noHumanName)])
    }

    func testBlankCardWithNoNameNoOrganizationIsExcludedAsNonPerson() {
        let contacts = [
            contactRecord(recordID: 4, phoneNumbers: ["+14155550030"])
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertEqual(result.excluded, [ExcludedContactCard(contactCardID: "uid-4", reason: .noHumanName)])
    }

    // A nickname alone is enough of a human signal, same as IdentityResolution.derivedName.
    func testNicknameAloneCountsAsAHumanName() {
        let contacts = [
            contactRecord(recordID: 5, nickname: "Foxy", phoneNumbers: ["+14155550040"])
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertEqual(result.people.first?.name, "Foxy")
    }

    func testShortcodeOnlyCardIsExcludedAsNonPerson() {
        let contacts = [
            contactRecord(recordID: 6, firstName: "Notice", lastName: "Alert", phoneNumbers: ["55512"])
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertEqual(result.excluded, [ExcludedContactCard(contactCardID: "uid-6", reason: .shortcode)])
    }

    func testAlphanumericSenderOnlyCardIsExcludedAsNonPerson() {
        let contacts = [
            contactRecord(recordID: 7, firstName: "Delivery", lastName: "Alert", phoneNumbers: ["USPSTRACK"])
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertEqual(result.excluded, [ExcludedContactCard(contactCardID: "uid-7", reason: .alphanumericSender)])
    }

    // MARK: - Identifier-less cards (real data: 7 of 253 have neither phone nor email)

    func testCardWithNoPhoneOrEmailButAHumanNameGetsAStableFallbackID() {
        let contacts = [
            contactRecord(recordID: 8, firstName: "Cass", lastName: "Ashcombe")
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertEqual(result.people.count, 1)
        XCTAssertEqual(result.people.first?.id, "contact:uid-8")
    }

    // MARK: - Determinism / no double counting among contact-only cards themselves

    func testTwoDifferentCardsSharingAnIdentifierProduceOnlyOneNode() {
        let contacts = [
            contactRecord(recordID: 9, uniqueID: "uid-a", firstName: "Dev", lastName: "Brenlow", phoneNumbers: ["+14155550050"]),
            contactRecord(recordID: 10, uniqueID: "uid-b", firstName: "Devon", lastName: "B", phoneNumbers: ["+14155550050"]),
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertEqual(result.people.count, 1)
        XCTAssertEqual(result.people.first?.contactCardID, "uid-a") // sorted uniqueID order: "uid-a" wins
        XCTAssertEqual(result.excluded, [ExcludedContactCard(contactCardID: "uid-b", reason: .duplicateWithinContactOnly)])
    }

    func testOutputIsSortedDeterministicallyById() {
        let contacts = [
            contactRecord(recordID: 11, firstName: "Zed", lastName: "Zephyr", phoneNumbers: ["+14155550099"]),
            contactRecord(recordID: 12, firstName: "Ann", lastName: "Alto", phoneNumbers: ["+14155550001"]),
        ]

        let result = ContactOnlyPeople.derive(contacts: contacts, matchedIdentifiers: [])

        XCTAssertEqual(result.people.map(\.id), ["+14155550001", "+14155550099"])
    }
}
