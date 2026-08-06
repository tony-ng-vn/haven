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

    // LinkedIn is the one platform Haven cannot reopen after a rename
    // (`PersonReach.openURL`), so a re-share with a changed slug is worth
    // catching by name even when the guessed name is not an exact fold --
    // this is the `NameSuggestion` machinery from the add sheet, reused here.
    @Test("a re-shared LinkedIn slug with a slightly different guessed name still offers the person")
    func closeNameMatch() {
        let sheet = model("https://www.linkedin.com/in/mai-trann-8a91b2")
        #expect(sheet.namePrefill == "Mai Trann")
        #expect(sheet.alreadyKnown == nil)
        #expect(sheet.nameMatches == [maiTran])
        #expect(sheet.isLinkRefreshOffer)
    }

    // A contact card's name is a fact Apple already has on file, not a guess
    // at a slug -- widening it to fuzzy would offer strangers who merely
    // sound alike, so a card keeps the exact fold `people(named:)` already
    // gave it.
    @Test("a contact card keeps the exact name match, not the fuzzy one")
    func contactCardStaysExact() {
        let sheet = ShareSheetModel(
            subject: .contact(name: "Mai Trann", platform: "phone", handleValue: "+1 415 555 0100"),
            mirror: directory
        )
        #expect(sheet.nameMatches.isEmpty)
        #expect(!sheet.isLinkRefreshOffer)
    }

    // The exact-handle path takes priority no matter how closely the guessed
    // name also reads: the account is already shown as who this is, and a
    // "same person?" offer to attach it to itself would be noise.
    @Test("an exact handle match wins over a name-only guess, even when both exist")
    func exactHandleWinsOverNameGuess() {
        let maiWithLinkedIn = MirrorPerson(
            id: "p4", name: "Mai Tran",
            handles: [MirrorHandle(platform: "linkedin", value: "mai-tran-8a91b2")]
        )
        let mirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0), people: [maiWithLinkedIn]
        )
        let sheet = ShareSheetModel(
            subject: ShareSubject(sharedURL: "https://www.linkedin.com/in/mai-tran-8a91b2")!,
            mirror: mirror
        )
        #expect(sheet.alreadyKnown?.id == "p4")
        #expect(sheet.nameMatches.isEmpty)
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

    // Offering a same-person match never applies it by itself: the person
    // still has to tap the row. Saving without picking one queues a brand
    // new person even though a match was on screen.
    @Test("a same-person offer is never auto-attached")
    func offerNeverAutoAttaches() {
        let sheet = model("https://www.linkedin.com/in/mai-tran-8a91b2")
        #expect(!sheet.nameMatches.isEmpty)
        guard case .profile(let profile)? = capture(sheet, name: "Mai Tran")?.payload else {
            Issue.record("expected a profile capture")
            return
        }
        #expect(profile.attachToPersonId == nil)
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

    // Reuses the same .manual payload a hand-typed WhatsApp or Telegram add
    // already queues -- no web profile to point at, and a note that is not
    // required the way a hand-typed add's is.
    @Test("a contact card saves through the manual payload, with no note required")
    func savesContact() {
        let sheet = ShareSheetModel(
            subject: .contact(name: "Tony Nguyen", platform: "phone", handleValue: "+1 415 555 0132"),
            mirror: directory
        )
        guard case .manual(let manual)? = capture(sheet, name: "Tony Nguyen")?.payload else {
            Issue.record("expected a manual capture")
            return
        }
        #expect(manual.name == "Tony Nguyen")
        #expect(manual.platform == "phone")
        #expect(manual.handleValue == "+1 415 555 0132")
        #expect(manual.profileUrl == "")
        #expect(manual.note == nil)
        // A contact card is exactly the source the drain forwards as
        // "imported" -- the person came off the device's own address book,
        // not something the user typed.
        #expect(manual.source == "imported")
        #expect(manual.platformId == nil)
    }
}

@Suite("What the share sheet does with a contact card")
struct ShareSheetContactTests {
    private func contactModel(
        name: String = "Mai Tran",
        platform: String = "phone",
        handleValue: String = "+84901234567",
        mirror: DirectoryMirror? = directory
    ) -> ShareSheetModel {
        ShareSheetModel(
            subject: .contact(name: name, platform: platform, handleValue: handleValue),
            mirror: mirror
        )
    }

    // Unlike a LinkedIn slug, which is a guess, the card's name is a fact --
    // still editable, same as every other prefill.
    @Test("the card's own name fills the name field")
    func namePrefill() {
        #expect(contactModel(name: "Tony Nguyen").namePrefill == "Tony Nguyen")
    }

    @Test("the identity line shows the handle the card carried")
    func identityLine() {
        #expect(contactModel(handleValue: "+84901234567").identityLine == "+84901234567")
    }

    @Test("a phone already on file names its person, keyed the same way a hand-typed add is")
    func alreadyKnownByPhone() {
        let phoneMirror = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [MirrorPerson(id: "p3", name: "Ada", handles: [MirrorHandle(platform: "phone", value: "+84901234567")])]
        )
        let sheet = contactModel(handleValue: "+84901234567", mirror: phoneMirror)
        #expect(sheet.alreadyKnown?.id == "p3")
        // Known fills the name field with the name on file, same as a
        // known profile share -- the field is showing who this is, not
        // asking.
        #expect(sheet.namePrefill == "Ada")
    }

    @Test("a phone nobody holds is somebody new")
    func notYetKnown() {
        #expect(contactModel(handleValue: "+1000000000").alreadyKnown == nil)
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

// LinkedIn's own app proved, on device, that it shares a profile as a
// message with the link inside it, never as a URL attachment -- ShareInput
// hands the whole message to `embeddedInText` rather than owning a second
// parser, so this is where that decision is actually checked.
@Suite("What a text share becomes")
struct ShareSubjectTextTests {
    @Test("LinkedIn's own message has the link inside a sentence")
    func linkedInMessage() {
        #expect(
            ShareSubject(
                embeddedInText:
                    "Tony Nguyen sent you this LinkedIn link: https://www.linkedin.com/in/tony-buildd"
            )
            == .profile(
                link: ProfileLink(platform: .linkedin, handle: "tony-buildd"),
                profileUrl: "https://www.linkedin.com/in/tony-buildd"
            )
        )
    }

    // A trailing period is the sentence ending, not part of the handle --
    // left on, this would silently save the wrong slug rather than fail to
    // parse at all.
    @Test("trailing sentence punctuation does not become part of the handle")
    func trailingPunctuation() {
        #expect(
            ShareSubject(embeddedInText: "Check out my profile: https://www.linkedin.com/in/tony-buildd.")
                == .profile(
                    link: ProfileLink(platform: .linkedin, handle: "tony-buildd"),
                    profileUrl: "https://www.linkedin.com/in/tony-buildd"
                )
        )
    }

    // A message that is nothing but the link, the way `sharedURL` already
    // accepts a bare scheme-less domain on its own.
    @Test("a bare scheme-less link on its own is still a subject")
    func bareLink() {
        #expect(
            ShareSubject(embeddedInText: "linkedin.com/in/tony-buildd")
                == .profile(
                    link: ProfileLink(platform: .linkedin, handle: "tony-buildd"),
                    profileUrl: "https://linkedin.com/in/tony-buildd"
                )
        )
    }

    // A link buried among other words -- a caption, not just a bare share --
    // is still found; the search is exhaustive, not "the first word only".
    @Test("a link among other words is still found")
    func linkAmongOtherWords() {
        #expect(
            ShareSubject(embeddedInText: "check this out https://instagram.com/mai.makes it's great")
                == .profile(
                    link: ProfileLink(platform: .instagram, handle: "mai.makes"),
                    profileUrl: "https://instagram.com/mai.makes"
                )
        )
    }

    @Test("a message with no link in it is not a subject")
    func noLink() {
        #expect(ShareSubject(embeddedInText: "great meeting you today!") == nil)
        #expect(ShareSubject(embeddedInText: "") == nil)
        #expect(ShareSubject(embeddedInText: "   ") == nil)
    }
}
