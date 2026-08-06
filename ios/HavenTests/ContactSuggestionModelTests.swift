import Contacts
import Foundation
import Testing
@testable import Haven

/// A fake address book that counts how often the one call this gate exists to
/// guard was actually made -- `ContactSuggestionModel` has no other way to
/// mislabel "became visible" as "newly added" than calling `newlySeenContacts`
/// at an authorization level where the two are indistinguishable.
private final class FakeAddressBook: AddressBookProviding, @unchecked Sendable {
    var status: CNAuthorizationStatus
    var discovery: ContactDiscovery
    private(set) var newlySeenCallCount = 0
    private(set) var knownIdentifierInputs: [Set<String>?] = []

    init(status: CNAuthorizationStatus, discovery: ContactDiscovery) {
        self.status = status
        self.discovery = discovery
    }

    func authorizationStatus() -> CNAuthorizationStatus { status }
    func search(matching query: String) async throws -> [AddressBookContact] { [] }
    func contacts(withIdentifiers identifiers: [String]) async -> [AddressBookContact] { [] }

    func newlySeenContacts(knownIdentifiers: Set<String>?) async -> ContactDiscovery {
        newlySeenCallCount += 1
        knownIdentifierInputs.append(knownIdentifiers)
        return discovery
    }
}

private func freshDefaults() -> UserDefaults {
    let suiteName = "haven.tests.contactSuggestionModel.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeQueue() -> (queue: CaptureQueue, root: URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("haven-suggestion-\(UUID().uuidString)")
    return (CaptureQueue(directory: root), root)
}

private let newContact = AddressBookContact(
    id: "c1", name: "Dun Dun", phones: ["+84901234567"], emails: []
)

@MainActor
@Suite("When the new-contact suggestion is allowed to check at all")
struct ContactSuggestionModelGateTests {
    // Limited access can grow for a reason that has nothing to do with a new
    // contact existing -- ContactAccessButton or the picker granting
    // visibility into someone already in the address book. Without a way to
    // tell that apart from a genuine add, this must skip entirely rather than
    // risk mislabeling the one as the other.
    @Test(".limited never calls newlySeenContacts and offers no suggestion")
    func limitedSkipsEntirely() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeAddressBook(
            status: .limited,
            discovery: ContactDiscovery(added: [newContact], allIdentifiers: ["c1"], historyToken: nil)
        )
        let changeState = ContactChangeState(userId: "u1", defaults: freshDefaults())
        let model = ContactSuggestionModel(
            userId: "u1", provider: fake, queue: queue, changeState: changeState, mirror: { nil }
        )

        await model.checkForSuggestion()

        #expect(fake.newlySeenCallCount == 0)
        #expect(model.suggestion == nil)
        // No baseline recorded either -- upgrading to full access later must
        // not read everything visible today as "just added".
        #expect(changeState.knownContactIdentifiers == nil)
    }

    @Test(".denied never calls newlySeenContacts")
    func deniedSkipsEntirely() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeAddressBook(
            status: .denied,
            discovery: ContactDiscovery(added: [newContact], allIdentifiers: ["c1"], historyToken: nil)
        )
        let changeState = ContactChangeState(userId: "u1", defaults: freshDefaults())
        let model = ContactSuggestionModel(
            userId: "u1", provider: fake, queue: queue, changeState: changeState, mirror: { nil }
        )

        await model.checkForSuggestion()

        #expect(fake.newlySeenCallCount == 0)
        #expect(model.suggestion == nil)
    }

    @Test(".authorized checks, records the baseline, and can offer a suggestion")
    func authorizedChecks() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeAddressBook(
            status: .authorized,
            discovery: ContactDiscovery(added: [newContact], allIdentifiers: ["c1"], historyToken: nil)
        )
        let changeState = ContactChangeState(userId: "u1", defaults: freshDefaults())
        let model = ContactSuggestionModel(
            userId: "u1", provider: fake, queue: queue, changeState: changeState, mirror: { nil }
        )

        await model.checkForSuggestion()

        #expect(fake.newlySeenCallCount == 1)
        #expect(model.suggestion?.id == "c1")
        #expect(changeState.knownContactIdentifiers == ["c1"])
    }

    @Test("a failed first read does not poison the next baseline")
    func failedFirstReadKeepsBaselineUnset() async throws {
        let (queue, root) = makeQueue()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeAddressBook(
            status: .authorized,
            discovery: ContactDiscovery(added: [], allIdentifiers: nil, historyToken: nil)
        )
        let changeState = ContactChangeState(userId: "u1", defaults: freshDefaults())
        let model = ContactSuggestionModel(
            userId: "u1", provider: fake, queue: queue, changeState: changeState, mirror: { nil }
        )

        await model.checkForSuggestion()
        #expect(changeState.knownContactIdentifiers == nil)

        fake.discovery = ContactDiscovery(added: [], allIdentifiers: ["c1"], historyToken: nil)
        await model.checkForSuggestion()

        #expect(fake.knownIdentifierInputs.count == 2)
        #expect(fake.knownIdentifierInputs[0] == nil)
        #expect(fake.knownIdentifierInputs[1] == nil)
        #expect(changeState.knownContactIdentifiers == ["c1"])
        #expect(model.suggestion == nil)
    }
}
