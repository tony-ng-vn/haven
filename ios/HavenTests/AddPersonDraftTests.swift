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

@Suite("What a hand-typed handle may be")
struct AddPersonCapTests {
    // The queue's rule: a capture that the server would refuse must never be
    // written, because the drain replays it with nobody there to be told. Every
    // platform's own parser has to land inside the server's handle cap.
    @Test("no platform can produce a handle the server would refuse")
    func everyPlatformFitsTheCap() {
        let long = String(repeating: "a", count: 200)
        for platform in AddPersonPlatform.allCases {
            guard let parsed = platform.parse(long) else { continue }
            #expect(
                HavenFieldCaps.fits(parsed, within: HavenFieldCaps.handle),
                "\(platform.rawValue) produced \(parsed.count) characters"
            )
        }
    }

    // Code points, not grapheme clusters and not UTF-16 units, because that is
    // how the server counts.
    @Test("the cap is counted the way the server counts it")
    func countsCodePoints() {
        #expect(HavenFieldCaps.fits(String(repeating: "a", count: 60), within: 60))
        #expect(!HavenFieldCaps.fits(String(repeating: "a", count: 61), within: 60))
        // One composed Vietnamese vowel is one code point, and one emoji is
        // one too. Neither costs two of the budget.
        #expect(HavenFieldCaps.fits("\u{1ec5}", within: 1))
    }
}

@Suite("What a field says when there is too much in it")
struct FieldCapMessageTests {
    // The message names the field and the number, the way the server's own
    // does. "Too long" without a number is a guessing game, and the round trip
    // that used to deliver the news arrived as "check your connection".
    @Test("the complaint names the field and the number")
    func namesBoth() {
        let message = HavenFieldCaps.tooLong("a name", max: HavenFieldCaps.name)
        #expect(message.contains("a name"))
        #expect(message.contains("40"))
    }

    // The caps are convex/fieldCaps.ts. A client that capped lower would refuse
    // what the server accepts; one that capped higher would let the server
    // throw, which is the bug this closes.
    @Test("the caps are the server's caps")
    func mirrorsTheServer() {
        #expect(HavenFieldCaps.name == 40)
        #expect(HavenFieldCaps.cityPart == 40)
        #expect(HavenFieldCaps.line == 60)
        #expect(HavenFieldCaps.handle == 60)
    }
}
