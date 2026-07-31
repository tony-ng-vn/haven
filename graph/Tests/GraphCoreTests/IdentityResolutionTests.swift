import XCTest
@testable import GraphCore

final class IdentityResolutionTests: XCTestCase {

    // uniqueID defaults from recordID so the many pre-existing calls below (all using
    // distinct recordIDs already) need no mechanical update; tests that care about the
    // multi-database shape (same recordID, different uniqueID) pass it explicitly.
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

    // The same identifier on two services (the multi-service duplicate) is one person
    // carrying both handle rowIDs.
    func testMultiServiceDuplicateMergesIntoOnePerson() {
        let handles = [
            RawHandle(rowID: 1, identifier: "+14155550001", service: "iMessage"),
            RawHandle(rowID: 2, identifier: "+14155550001", service: "SMS"),
        ]

        let result = IdentityResolution.resolve(handles: handles, contacts: [])

        XCTAssertEqual(result.people.count, 1)
        let person = try? XCTUnwrap(result.people.first)
        XCTAssertEqual(person?.handleRowIDs, [1, 2])
        XCTAssertEqual(person?.identifiers, ["+14155550001"])
    }

    // A card co-listing a phone and an email, plus two handles on different services (one
    // per identifier), chains into ONE person with the card's name and photo attached.
    func testPhoneEmailCoListedCardChainsHandlesIntoOnePersonWithNameAndPhoto() {
        let handles = [
            RawHandle(rowID: 1, identifier: "(415) 555-0002", service: "iMessage"),
            RawHandle(rowID: 2, identifier: "alice@example.com", service: "SMS"),
        ]
        let photo = Data([0x01, 0x02, 0x03])
        let contacts = [
            contactRecord(
                recordID: 10,
                firstName: "Alice",
                lastName: "Anderson",
                phoneNumbers: ["+14155550002"],
                emails: ["Alice@Example.com"],
                thumbnailImageData: photo
            )
        ]

        let result = IdentityResolution.resolve(handles: handles, contacts: contacts)

        XCTAssertEqual(result.people.count, 1)
        let person = try? XCTUnwrap(result.people.first)
        XCTAssertEqual(person?.handleRowIDs, [1, 2])
        XCTAssertEqual(person?.name, "Alice Anderson")
        XCTAssertEqual(person?.thumbnailImageData, photo)
        XCTAssertEqual(person?.contactCardIDs, ["uid-10"])
        XCTAssertTrue(person?.hasContactCard ?? false)
        XCTAssertTrue(person?.identifiers.contains("+14155550002") ?? false)
        XCTAssertTrue(person?.identifiers.contains("alice@example.com") ?? false)
    }

    // Two people with the same card-derived full name but disjoint cards: a merge
    // candidate is queued, and they remain two separate people (never auto-merged).
    func testSameCardDerivedNameDisjointCardsProducesMergeCandidateAndStaysTwoPeople() {
        let handles = [
            RawHandle(rowID: 1, identifier: "+14155550003", service: "iMessage"),
            RawHandle(rowID: 2, identifier: "+14155550004", service: "iMessage"),
        ]
        let contacts = [
            contactRecord(recordID: 20, firstName: "John", lastName: "Smith", phoneNumbers: ["+14155550003"]),
            contactRecord(recordID: 21, firstName: "john", lastName: "smith", phoneNumbers: ["+14155550004"]),
        ]

        let result = IdentityResolution.resolve(handles: handles, contacts: contacts)

        XCTAssertEqual(result.people.count, 2)
        XCTAssertEqual(result.mergeCandidates.count, 1)

        let candidate = try? XCTUnwrap(result.mergeCandidates.first)
        let personIDs = Set(result.people.map(\.id))
        XCTAssertTrue(personIDs.contains(candidate?.personID1 ?? ""))
        XCTAssertTrue(personIDs.contains(candidate?.personID2 ?? ""))
        XCTAssertNotEqual(candidate?.personID1, candidate?.personID2)
    }

    // A handle with no matching card yields a person with nil name and no contact card.
    func testHandleWithNoCardYieldsPersonWithNilNameAndNoContactCard() {
        let handles = [
            RawHandle(rowID: 1, identifier: "+14155550005", service: "iMessage"),
        ]

        let result = IdentityResolution.resolve(handles: handles, contacts: [])

        XCTAssertEqual(result.people.count, 1)
        let person = try? XCTUnwrap(result.people.first)
        XCTAssertNil(person?.name)
        XCTAssertFalse(person?.hasContactCard ?? true)
        XCTAssertNil(person?.thumbnailImageData)
        XCTAssertTrue(person?.contactCardIDs.isEmpty ?? false)
    }

    // A card-only phone number with no matching handle produces no person at all.
    func testCardOnlyPhoneWithNoHandleProducesNoPerson() {
        let contacts = [
            contactRecord(recordID: 30, firstName: "Nobody", lastName: "Contacted", phoneNumbers: ["+14155550006"])
        ]

        let result = IdentityResolution.resolve(handles: [], contacts: contacts)

        XCTAssertTrue(result.people.isEmpty)
    }

    // Same input, resolved twice, must produce identical output.
    func testResolutionIsDeterministicAcrossRuns() {
        let handles = [
            RawHandle(rowID: 1, identifier: "+14155550007", service: "iMessage"),
            RawHandle(rowID: 2, identifier: "bob@example.com", service: "SMS"),
            RawHandle(rowID: 3, identifier: "12345", service: "SMS"),
        ]
        let contacts = [
            contactRecord(recordID: 40, firstName: "Bob", phoneNumbers: ["+14155550007"], emails: ["bob@example.com"])
        ]

        let first = IdentityResolution.resolve(handles: handles, contacts: contacts)
        let second = IdentityResolution.resolve(handles: handles, contacts: contacts)

        // Pin the actual expected shape, not just self-consistency: two internal Dictionary/Set
        // iteration orders happening to agree within one process run would make a bare
        // first == second pass even from a non-deterministic implementation.
        XCTAssertEqual(first.people.map(\.id), ["+14155550007", "12345"])
        XCTAssertEqual(first.people.first { $0.id == "+14155550007" }?.handleRowIDs, [1, 2])
        XCTAssertEqual(first.people.first { $0.id == "12345" }?.handleRowIDs, [3])

        XCTAssertEqual(first, second)
    }

    // The real Contacts store is three separate databases, each with its own Z_PK space;
    // the CLI concatenates their records. Two cards with the SAME recordID (5) but
    // different uniqueIDs (the two-database shape) must resolve as two distinct people,
    // not crash a Dictionary(uniqueKeysWithValues:) keyed on the collidable recordID.
    func testSameRecordIDFromTwoDatabasesProducesTwoDistinctPeople() {
        let handles = [
            RawHandle(rowID: 1, identifier: "+14155550010", service: "iMessage"),
            RawHandle(rowID: 2, identifier: "+14155550011", service: "iMessage"),
        ]
        let contacts = [
            contactRecord(recordID: 5, uniqueID: "db1-uid-5", firstName: "Alice", lastName: "First", phoneNumbers: ["+14155550010"]),
            contactRecord(recordID: 5, uniqueID: "db2-uid-5", firstName: "Bob", lastName: "Second", phoneNumbers: ["+14155550011"]),
        ]

        let result = IdentityResolution.resolve(handles: handles, contacts: contacts)

        XCTAssertEqual(result.people.count, 2)
        let names = Set(result.people.compactMap(\.name))
        XCTAssertEqual(names, ["Alice First", "Bob Second"])
    }
}
