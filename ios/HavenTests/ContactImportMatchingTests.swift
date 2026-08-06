import Foundation
import Testing
@testable import Haven

private func contact(
    id: String = "c1",
    name: String = "Tony Nguyen",
    phones: [String] = [],
    emails: [String] = []
) -> AddressBookContact {
    AddressBookContact(id: id, name: name, phones: phones, emails: emails)
}

@Suite("Which handle a device contact imports under")
struct ContactHandleTests {
    // Phone is the stronger key -- less likely to be entered two different
    // ways by two different apps than an email, same rule VCardContact uses.
    @Test("a contact with both a phone and an email is keyed on the phone")
    func phoneWinsOverEmail() {
        let person = contact(phones: ["+1 415 555 0132"], emails: ["tony@example.com"])
        #expect(ContactImportMatching.handle(for: person) == .phone("+1 415 555 0132"))
    }

    @Test("a contact with only an email is keyed on the email")
    func emailWhenNoPhone() {
        let person = contact(emails: ["tony@example.com"])
        #expect(ContactImportMatching.handle(for: person) == .email("tony@example.com"))
    }

    @Test("a contact with neither a phone nor an email has no handle")
    func nothingToKeyOn() {
        #expect(ContactImportMatching.handle(for: contact()) == nil)
    }
}

@Suite("Whether the mirror already covers a device contact")
struct ContactAlreadyInHavenTests {
    private let ada = MirrorPerson(
        id: "p1", name: "Ada",
        handles: [MirrorHandle(platform: "phone", value: "+14155550132")]
    )
    private let mai = MirrorPerson(
        id: "p2", name: "Mai",
        handles: [MirrorHandle(platform: "email", value: "mai@example.com")]
    )
    private var mirror: DirectoryMirror {
        DirectoryMirror(refreshedAt: Date(timeIntervalSince1970: 0), people: [ada, mai])
    }

    // The dedup key: a phone that only differs from what is on file by
    // formatting still resolves to the same person, the same normalization
    // ConvexCaptureSink applies at drain time.
    @Test("a phone already on file, differently formatted, still matches")
    func phoneMatchesDespiteFormatting() {
        let person = contact(phones: ["+1 (415) 555-0132"])
        #expect(ContactImportMatching.alreadyInHaven(person, mirror: mirror) == ada)
    }

    @Test("an email already on file matches")
    func emailMatches() {
        let person = contact(emails: ["mai@example.com"])
        #expect(ContactImportMatching.alreadyInHaven(person, mirror: mirror) == mai)
    }

    @Test("a phone and email nobody holds is not covered")
    func notCovered() {
        let person = contact(phones: ["+84901234567"], emails: ["stranger@example.com"])
        #expect(ContactImportMatching.alreadyInHaven(person, mirror: mirror) == nil)
    }

    @Test("no mirror yet means nobody is covered")
    func noMirror() {
        #expect(ContactImportMatching.alreadyInHaven(contact(phones: ["+14155550132"]), mirror: nil) == nil)
    }
}

@Suite("Which device contacts are worth offering as an import row")
struct ContactImportCandidatesTests {
    @Test("a contact already in Haven is not a distinct row")
    func suppressesAlreadyKnown() {
        let known = MirrorPerson(
            id: "p1", name: "Ada", handles: [MirrorHandle(platform: "phone", value: "+14155550132")]
        )
        let mirror = DirectoryMirror(refreshedAt: Date(timeIntervalSince1970: 0), people: [known])
        let contacts = [
            contact(id: "c1", name: "Ada", phones: ["+14155550132"]),
            contact(id: "c2", name: "Someone New", phones: ["+84901234567"]),
        ]
        let rows = ContactImportMatching.importCandidates(from: contacts, mirror: mirror)
        #expect(rows.map(\.id) == ["c2"])
    }

    @Test("a contact with no phone and no email is never a row")
    func suppressesNoHandle() {
        let contacts = [contact(id: "c1", name: "No Way To Reach")]
        #expect(ContactImportMatching.importCandidates(from: contacts, mirror: nil).isEmpty)
    }

    @Test("a contact with a blank name is never a row")
    func suppressesBlankName() {
        let contacts = [contact(id: "c1", name: "   ", phones: ["+14155550132"])]
        #expect(ContactImportMatching.importCandidates(from: contacts, mirror: nil).isEmpty)
    }
}

@Suite("What a one-tap import queues")
struct ContactImportCaptureTests {
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let now = Date(timeIntervalSince1970: 1_700)

    @Test("a phone contact queues a manual capture with a raw, unnormalized handle")
    func phoneCapture() {
        let person = contact(name: "Tony Nguyen", phones: ["+1 415 555 0132"])
        let capture = ContactImportMatching.capture(for: person, id: id, capturedAt: now)
        guard case .manual(let manual)? = capture?.payload else {
            Issue.record("expected a manual capture")
            return
        }
        #expect(capture?.id == id)
        #expect(capture?.capturedAt == now)
        #expect(manual.name == "Tony Nguyen")
        #expect(manual.platform == "phone")
        #expect(manual.handleValue == "+1 415 555 0132")
        #expect(manual.profileUrl == "")
        #expect(manual.note == nil)
        #expect(manual.attachToPersonId == nil)
        // A one-tap import is Contacts, not a share and not something typed,
        // and the server treats that as one of three distinct provenances.
        #expect(manual.source == "imported")
    }

    @Test("an email-only contact queues a manual capture keyed on the email")
    func emailCapture() {
        let person = contact(name: "Mai Tran", emails: ["mai@example.com"])
        guard case .manual(let manual)? = ContactImportMatching.capture(for: person, id: id, capturedAt: now)?
            .payload
        else {
            Issue.record("expected a manual capture")
            return
        }
        #expect(manual.platform == "email")
        #expect(manual.handleValue == "mai@example.com")
    }

    @Test("a contact with no handle queues nothing")
    func noHandleNoCapture() {
        #expect(ContactImportMatching.capture(for: contact(name: "Nobody Reachable")) == nil)
    }

    @Test("a blank name queues nothing, even with a phone")
    func blankNameNoCapture() {
        #expect(ContactImportMatching.capture(for: contact(name: "  ", phones: ["+14155550132"])) == nil)
    }
}

@Suite("Every phone and email the mirror already holds")
struct DirectoryMirrorKnownHandlesTests {
    @Test("phones and emails are collected across every person, folded by platform")
    func collectsAcrossPeople() {
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [
                MirrorPerson(
                    id: "p1", name: "Ada",
                    handles: [
                        MirrorHandle(platform: "phone", value: "+14155550132"),
                        MirrorHandle(platform: "instagram", value: "ada.codes"),
                    ]
                ),
                MirrorPerson(
                    id: "p2", name: "Mai",
                    handles: [MirrorHandle(platform: "Email", value: "mai@example.com")]
                ),
            ]
        )
        let known = mirror.knownPhonesAndEmails
        #expect(known.phones == ["+14155550132"])
        #expect(known.emails == ["mai@example.com"])
    }
}
