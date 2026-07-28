import Foundation
import Testing
@testable import Haven

private let mai = MirrorPerson(
    id: "p1",
    name: "Nguy\u{1ec5}n Mai",
    handles: [MirrorHandle(platform: "instagram", value: "mai.makes")]
)
private let maiTran = MirrorPerson(id: "p2", name: "Mai Tran", handles: [])

private let directory = DirectoryMirror(
    refreshedAt: Date(timeIntervalSince1970: 1_000),
    people: [mai, maiTran]
)

private func model(
    _ url: String,
    mirror: DirectoryMirror? = directory
) -> ShareSheetModel {
    ShareSheetModel(
        subject: ShareSubject(sharedURL: url)!,
        mirror: mirror
    )
}

@Suite("What the share sheet opens on")
struct ShareSheetOpeningTests {
    // The name field is a confirmation, not automation, and only LinkedIn
    // gives it anything worth confirming: the slug carries the person's name.
    @Test("a LinkedIn slug fills the name field")
    func linkedInPrefill() {
        #expect(model("https://www.linkedin.com/in/mai-tran-8a91b2").namePrefill == "Mai Tran")
    }

    // Instagram and X hand over a handle and nothing else. A field prefilled
    // with a handle looks like a name without being one, so a fast tap-through
    // would save a person literally named after their account. Empty is the
    // honest state, and the handle goes in the line underneath, where it is
    // true.
    @Test("a handle is never offered as a name")
    func handleIsNotAName() {
        #expect(model("https://instagram.com/stranger").namePrefill == "")
        #expect(model("https://x.com/mai_makes").namePrefill == "")
    }

    @Test("the identity line says the account, which is the part we know")
    func identityLine() {
        #expect(model("https://instagram.com/mai.makes").identityLine == "@mai.makes on Instagram")
        #expect(model("https://x.com/mai_makes").identityLine == "@mai_makes on X")
        #expect(
            model("https://www.linkedin.com/in/mai-tran-8a91b2").identityLine
                == "linkedin.com/in/mai-tran-8a91b2"
        )
    }

    // A slug that is nothing but id junk guesses nothing, and an empty field
    // is better than a wrong one.
    @Test("a LinkedIn slug with no name in it fills nothing")
    func noGuess() {
        #expect(model("https://www.linkedin.com/in/8a91b2").namePrefill == "")
    }
}

@Suite("Who the share sheet thinks this is")
struct ShareSheetIdentityTests {
    // The one thing the mirror is sure of. The server keys on exactly this
    // pair, so a match here is the same answer the save will give.
    @Test("an account already in the directory names its person")
    func alreadyKnown() {
        #expect(model("https://instagram.com/mai.makes").alreadyKnown == mai)
    }

    @Test("an account nobody holds is somebody new")
    func notKnown() {
        #expect(model("https://instagram.com/stranger").alreadyKnown == nil)
    }

    // Then the name field is not asking who this is, it is showing who it
    // already is.
    @Test("a known account fills the name field with the name on file")
    func knownFillsName() {
        #expect(model("https://instagram.com/mai.makes").namePrefill == "Nguy\u{1ec5}n Mai")
    }

    // A guessed name is a suggestion and is offered as one -- Haven never
    // decides two people are one.
    @Test("a guessed name offers the person it might be")
    func nameMatch() {
        let sheet = model("https://www.linkedin.com/in/mai-tran-8a91b2")
        #expect(sheet.alreadyKnown == nil)
        #expect(sheet.nameMatches == [maiTran])
    }

    // Offering to attach somebody to themselves is noise: they are already
    // shown as the person this is.
    @Test("a known account offers nobody to attach to")
    func noSuggestionWhenKnown() {
        #expect(model("https://instagram.com/mai.makes").nameMatches.isEmpty)
    }

    // Before the app has ever synced there is no mirror, and the sheet still
    // has to open and still has to save.
    @Test("no mirror yet is nobody, not a broken sheet")
    func noMirror() {
        let sheet = model("https://instagram.com/mai.makes", mirror: nil)
        #expect(sheet.alreadyKnown == nil)
        #expect(sheet.nameMatches.isEmpty)
        #expect(sheet.namePrefill == "")
        #expect(sheet.search("mai").isEmpty)
    }

    @Test("the search field reaches the rest of the directory")
    func search() {
        #expect(model("https://instagram.com/stranger").search("mai").map(\.id) == ["p1", "p2"])
    }
}

@Suite("What the share sheet saves")
struct ShareSheetSaveTests {
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let now = Date(timeIntervalSince1970: 1_700)

    private func capture(
        _ sheet: ShareSheetModel,
        name: String,
        note: String = "",
        attachTo: MirrorPerson? = nil
    ) -> QueuedCapture? {
        sheet.capture(name: name, note: note, attachTo: attachTo, id: id, capturedAt: now)
    }

    // The server requires a name and throws without one. A capture queued
    // without one could never drain -- it would retry forever and the user
    // would never be told. Refusing to queue it is the only honest option.
    @Test("a capture with no name is never queued")
    func nameRequired() {
        let sheet = model("https://instagram.com/mai.makes")
        #expect(capture(sheet, name: "") == nil)
        #expect(capture(sheet, name: "   ") == nil)
        #expect(!sheet.canSave(name: ""))
        #expect(sheet.canSave(name: "Mai"))
    }

    @Test("a saved profile carries everything the mutation takes")
    func savesProfile() {
        let sheet = model("https://instagram.com/mai.makes")
        let queued = capture(sheet, name: "  Mai Tran  ", note: "  ceramics, Hanoi meetup  ")

        #expect(queued?.id == id)
        #expect(queued?.capturedAt == now)
        guard case .profile(let profile)? = queued?.payload else {
            Issue.record("expected a profile capture")
            return
        }
        #expect(profile.link == ProfileLink(platform: .instagram, handle: "mai.makes"))
        #expect(profile.profileUrl == "https://instagram.com/mai.makes")
        #expect(profile.name == "Mai Tran")
        #expect(profile.note == "ceramics, Hanoi meetup")
        #expect(profile.attachToPersonId == nil)
    }

    // An empty note is no note, not an empty one: the server would store a
    // blank line in the person's context.
    @Test("a note nobody typed is no note")
    func emptyNote() {
        let sheet = model("https://instagram.com/mai.makes")
        guard case .profile(let profile)? = capture(sheet, name: "Mai", note: "   ")?.payload
        else {
            Issue.record("expected a profile capture")
            return
        }
        #expect(profile.note == nil)
    }

    @Test("attaching records who the user picked")
    func attach() {
        let sheet = model("https://www.linkedin.com/in/mai-tran-8a91b2")
        guard case .profile(let profile)? = capture(sheet, name: "Mai Tran", attachTo: maiTran)?
            .payload
        else {
            Issue.record("expected a profile capture")
            return
        }
        #expect(profile.attachToPersonId == "p2")
    }

    // Re-sharing an account already on file is not an error and not a no-op:
    // the note the user just typed is the whole point, and the server appends
    // it to the person they already have.
    @Test("re-sharing a known account still saves the note")
    func reshare() {
        let sheet = model("https://instagram.com/mai.makes")
        guard case .profile(let profile)? = capture(
            sheet, name: "Nguy\u{1ec5}n Mai", note: "moved to Da Nang"
        )?.payload else {
            Issue.record("expected a profile capture")
            return
        }
        #expect(profile.note == "moved to Da Nang")
    }

    @Test("a screenshot carries its file and its note")
    func savesScreenshot() {
        let sheet = ShareSheetModel(
            subject: .screenshot(fileName: "abc.png"), mirror: directory
        )
        guard case .screenshot(let screenshot)? = capture(
            sheet, name: "Mai Tran", note: "badge said Mai"
        )?.payload else {
            Issue.record("expected a screenshot capture")
            return
        }
        #expect(screenshot.fileName == "abc.png")
        #expect(screenshot.note == "badge said Mai")
    }
}

@Suite("What the share sheet was handed")
struct ShareSubjectTests {
    @Test("a profile URL from any of the three apps is a subject")
    func profileURL() {
        #expect(
            ShareSubject(sharedURL: "x.com/mai_makes?s=11")
                == .profile(
                    link: ProfileLink(platform: .x, handle: "mai_makes"),
                    profileUrl: "https://x.com/mai_makes"
                )
        )
    }

    // The tracking noise is stripped from what is stored, so re-sharing the
    // same person twice does not file two different URLs against them.
    @Test("the stored URL is the profile, not the share link")
    func canonicalURL() {
        #expect(
            ShareSubject(
                sharedURL:
                    "https://www.linkedin.com/in/mai-tran-8a91b2?utm_source=share_via&utm_medium=member_ios"
            )
            == .profile(
                link: ProfileLink(platform: .linkedin, handle: "mai-tran-8a91b2"),
                profileUrl: "https://www.linkedin.com/in/mai-tran-8a91b2"
            )
        )
        #expect(
            ShareSubject(sharedURL: "https://www.instagram.com/mai.makes/?igsh=MXc4b2k5")
                == .profile(
                    link: ProfileLink(platform: .instagram, handle: "mai.makes"),
                    profileUrl: "https://www.instagram.com/mai.makes"
                )
        )
    }

    // A shared post is content, and capturing its author as a person the user
    // met would be a lie about where they know them from.
    @Test("anything that is not one person's profile is not a subject")
    func notAProfile() {
        #expect(ShareSubject(sharedURL: "https://x.com/mai_makes/status/17999") == nil)
        #expect(ShareSubject(sharedURL: "https://facebook.com/mai") == nil)
        #expect(ShareSubject(sharedURL: "met at the conference") == nil)
    }
}
