import Foundation
import Testing
@testable import Haven

private let mai = MirrorPerson(
    id: "p1",
    name: "Nguy\u{1ec5}n Mai",
    handles: [MirrorHandle(platform: "instagram", value: "mai.makes")]
)
private let maiAgain = MirrorPerson(id: "p2", name: "Nguyen Mai", handles: [])

private let mirror = DirectoryMirror(
    refreshedAt: Date(timeIntervalSince1970: 1_000),
    people: [mai, maiAgain]
)

private func filled(
    name: String = "Mai Tran",
    platform: AddPersonPlatform = .instagram,
    handleText: String = "mai.makes",
    note: String = "met at the Hanoi meetup"
) -> AddPersonDraft {
    AddPersonDraft(name: name, platform: platform, handleText: handleText, note: note)
}

@Suite("Saving somebody by hand")
struct AddPersonDraftTests {
    // The spec's three required fields. Save stays off until all three are
    // there, because a person with no handle or no note is a row nobody ever
    // retrieves.
    @Test("all three fields are required before there is anything to save")
    func requiresAllThree() {
        #expect(filled().canSave)
        #expect(!filled(name: "   ").canSave)
        #expect(!filled(handleText: "").canSave)
        #expect(!filled(note: " \n ").canSave)
    }

    @Test("a draft that cannot be saved produces no capture")
    func noCaptureWithoutTheFields() {
        #expect(filled(note: "").capture() == nil)
        #expect(filled(handleText: "!!!").capture() == nil)
    }

    // A pasted profile link is the normal thing to do, and what gets stored is
    // the handle the server dedups on rather than the URL.
    @Test("a pasted link is reduced to the handle on every platform")
    func parsesPastedLinks() {
        #expect(filled(platform: .instagram, handleText: "instagram.com/mai.makes").handle == "mai.makes")
        #expect(filled(platform: .x, handleText: "https://twitter.com/mai_makes").handle == "mai_makes")
        #expect(
            filled(platform: .linkedin, handleText: "https://www.linkedin.com/in/mai-tran-8a91b2")
                .handle == "mai-tran-8a91b2"
        )
        #expect(filled(platform: .telegram, handleText: "https://t.me/mai_makes").handle == "mai_makes")
    }

    // The asymmetry mvp-design names: your own card offers four platforms, a
    // person you save by hand can carry any handle worth recording.
    @Test("WhatsApp and Telegram are savable platforms")
    func freeFormPlatforms() {
        #expect(filled(platform: .whatsapp, handleText: "+84 90 123 4567").handle == "+84901234567")
        #expect(filled(platform: .telegram, handleText: "@mai_makes").handle == "mai_makes")
        // Telegram's own rule, so a four-character handle is refused here
        // rather than by the server after the sheet has already closed.
        #expect(filled(platform: .telegram, handleText: "mai").handle == nil)
    }

    // The link is the only way back to the profile a hand-typed person came
    // from, and the server never overwrites one it already has.
    @Test("a handle carries the address it points at, where there is one")
    func profileUrls() {
        #expect(filled(platform: .instagram).capture()?.manual?.profileUrl == "https://instagram.com/mai.makes")
        #expect(
            filled(platform: .whatsapp, handleText: "+84901234567").capture()?.manual?.profileUrl
                == "https://wa.me/84901234567"
        )
        // A phone number is not an address, so nothing is claimed to be one.
        #expect(filled(platform: .phone, handleText: "+84901234567").capture()?.manual?.profileUrl == "")
    }

    @Test("the capture carries exactly what was typed, trimmed")
    func capturePayload() throws {
        let capture = filled(name: "  Mai Tran  ", note: "  met at the Hanoi meetup  ").capture()
        let manual = try #require(capture?.manual)
        #expect(manual.name == "Mai Tran")
        #expect(manual.note == "met at the Hanoi meetup")
        #expect(manual.platform == "instagram")
        #expect(manual.handleValue == "mai.makes")
        #expect(manual.attachToPersonId == nil)
    }

    @Test("attaching to somebody records who was chosen")
    func attaching() throws {
        let manual = try #require(filled().capture(attachTo: maiAgain)?.manual)
        #expect(manual.attachToPersonId == "p2")
    }

    // The dedup the share sheet gets, in the app: the account says who this is
    // however stale the mirror's names are.
    @Test("a handle already on file names the person who holds it")
    func alreadyKnown() {
        #expect(filled(handleText: "@MAI.MAKES").alreadyKnown(in: mirror) == mai)
        #expect(filled(handleText: "stranger").alreadyKnown(in: mirror) == nil)
        // The same text on a platform they are not on is somebody else.
        #expect(filled(platform: .x, handleText: "mai.makes").alreadyKnown(in: mirror) == nil)
    }

    // Offered rather than applied, and only while the account itself is not
    // already on file: once the server knows who this is, asking is noise.
    @Test("a typed name offers the people already stored under it")
    func nameMatches() {
        #expect(filled(name: "nguyen mai", handleText: "stranger").nameMatches(in: mirror) == [mai, maiAgain])
        #expect(filled(name: "nguyen mai", handleText: "mai.makes").nameMatches(in: mirror).isEmpty)
        #expect(filled(name: "nobody", handleText: "stranger").nameMatches(in: mirror).isEmpty)
    }

    @Test("no mirror is an ordinary answer, not a failure")
    func noMirror() {
        #expect(filled().alreadyKnown(in: nil) == nil)
        #expect(filled().nameMatches(in: nil).isEmpty)
        #expect(filled().capture() != nil)
    }
}

private extension QueuedCapture {
    var manual: QueuedCapture.Manual? {
        guard case .manual(let manual) = payload else { return nil }
        return manual
    }
}
