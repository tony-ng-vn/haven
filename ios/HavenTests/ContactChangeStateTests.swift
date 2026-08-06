import Foundation
import Testing
@testable import Haven

/// An isolated defaults suite per test, so bookkeeping tests never share state
/// with each other or with the real App Group suite -- the same reason
/// `CaptureQueueTests` writes to a throwaway directory rather than the real
/// container.
private func freshDefaults() -> UserDefaults {
    let suiteName = "haven.tests.contactChangeState.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@Suite("Change-history token bookkeeping")
struct ContactChangeStateTokenTests {
    @Test("no token before the first fetch")
    func noTokenYet() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        #expect(state.historyToken == nil)
    }

    @Test("a stored token round-trips")
    func roundTrips() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        let token = Data([1, 2, 3])
        state.historyToken = token
        #expect(state.historyToken == token)
    }

    @Test("two accounts on one device keep separate tokens")
    func scopedPerUser() {
        let defaults = freshDefaults()
        let mine = ContactChangeState(userId: "mine", defaults: defaults)
        let theirs = ContactChangeState(userId: "theirs", defaults: defaults)
        mine.historyToken = Data([9])
        #expect(theirs.historyToken == nil)
    }
}

@Suite("Known-contact-identifier bookkeeping")
struct ContactChangeStateKnownIdentifiersTests {
    @Test("no baseline before the first check")
    func noBaselineYet() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        #expect(state.knownContactIdentifiers == nil)
    }

    @Test("a recorded baseline round-trips, even when empty")
    func roundTrips() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        state.recordKnownContactIdentifiers([])
        // Empty and nil are different facts: empty means "checked, found
        // nobody" and nil means "never checked at all" -- collapsing them
        // would make an address book with nobody in it look unchecked
        // forever.
        #expect(state.knownContactIdentifiers == [])
    }

    @Test("a non-empty baseline round-trips")
    func nonEmptyRoundTrips() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        state.recordKnownContactIdentifiers(["c1", "c2"])
        #expect(state.knownContactIdentifiers == ["c1", "c2"])
    }

    @Test("two accounts on one device keep separate baselines")
    func scopedPerUser() {
        let defaults = freshDefaults()
        let mine = ContactChangeState(userId: "mine", defaults: defaults)
        let theirs = ContactChangeState(userId: "theirs", defaults: defaults)
        mine.recordKnownContactIdentifiers(["c1"])
        #expect(theirs.knownContactIdentifiers == nil)
    }
}

@Suite("Diffing newly seen contact identifiers")
struct ContactIdentifierDiffTests {
    // The rule that keeps the first-ever check from reading the whole
    // address book as "just added": no baseline means nothing is reported,
    // not everything.
    @Test("no baseline yet reports nothing added, establishing one instead")
    func firstCheckReportsNothing() {
        #expect(ContactIdentifierDiff.added(current: ["c1", "c2"], knownBefore: nil).isEmpty)
    }

    @Test("identifiers present now but not in the baseline are new")
    func reportsGenuinelyNew() {
        #expect(
            ContactIdentifierDiff.added(current: ["c1", "c2", "c3"], knownBefore: ["c1", "c2"]) == ["c3"]
        )
    }

    @Test("nothing changed since the baseline means nothing new")
    func noChange() {
        #expect(ContactIdentifierDiff.added(current: ["c1"], knownBefore: ["c1"]).isEmpty)
    }

    @Test("a contact that left the address book is not reported as added")
    func removedIsNotAdded() {
        #expect(ContactIdentifierDiff.added(current: [], knownBefore: ["c1"]).isEmpty)
    }
}

@Suite("Suggestion dismissal memory")
struct ContactChangeStateDismissalTests {
    @Test("a contact is not dismissed until it is")
    func notDismissedByDefault() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        #expect(state.isDismissed("c1") == false)
    }

    @Test("dismissing remembers, so nothing is suggested twice")
    func dismissRemembers() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        state.dismiss("c1")
        #expect(state.isDismissed("c1"))
    }

    @Test("dismissing one contact does not dismiss another")
    func dismissalIsPerContact() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        state.dismiss("c1")
        #expect(state.isDismissed("c2") == false)
    }

    @Test("dismissing the same contact twice is not an error")
    func dismissTwice() {
        let state = ContactChangeState(userId: "u1", defaults: freshDefaults())
        state.dismiss("c1")
        state.dismiss("c1")
        #expect(state.isDismissed("c1"))
    }

    @Test("two accounts on one device keep separate dismissals")
    func scopedPerUser() {
        let defaults = freshDefaults()
        let mine = ContactChangeState(userId: "mine", defaults: defaults)
        let theirs = ContactChangeState(userId: "theirs", defaults: defaults)
        mine.dismiss("c1")
        #expect(theirs.isDismissed("c1") == false)
    }
}

@Suite("Picking the one suggestion to show")
struct ContactSuggestionPickTests {
    private func contact(id: String, name: String = "Someone", phones: [String] = ["+14155550132"]) -> AddressBookContact {
        AddressBookContact(id: id, name: name, phones: phones, emails: [])
    }

    @Test("the first eligible contact is picked, never more than one")
    func picksFirstEligible() {
        let added = [contact(id: "c1"), contact(id: "c2")]
        #expect(
            ContactSuggestion.pick(from: added, mirror: nil, isDismissed: { _ in false })?.id == "c1"
        )
    }

    @Test("a dismissed contact is skipped in favor of the next one")
    func skipsDismissed() {
        let added = [contact(id: "c1"), contact(id: "c2")]
        let picked = ContactSuggestion.pick(from: added, mirror: nil, isDismissed: { $0 == "c1" })
        #expect(picked?.id == "c2")
    }

    @Test("a contact already in Haven is never suggested")
    func skipsAlreadyKnown() {
        let known = MirrorPerson(
            id: "p1", name: "Someone", handles: [MirrorHandle(platform: "phone", value: "+14155550132")]
        )
        let mirror = DirectoryMirror(refreshedAt: Date(timeIntervalSince1970: 0), people: [known])
        let added = [contact(id: "c1")]
        #expect(ContactSuggestion.pick(from: added, mirror: mirror, isDismissed: { _ in false }) == nil)
    }

    @Test("a contact with no phone and no email is never suggested")
    func skipsNoHandle() {
        let added = [contact(id: "c1", phones: [])]
        #expect(ContactSuggestion.pick(from: added, mirror: nil, isDismissed: { _ in false }) == nil)
    }

    @Test("nothing new means nothing to suggest")
    func nothingAdded() {
        #expect(ContactSuggestion.pick(from: [], mirror: nil, isDismissed: { _ in false }) == nil)
    }
}
