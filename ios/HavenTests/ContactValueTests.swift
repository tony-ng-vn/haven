import Foundation
import Testing
@testable import Haven

// The contact question's rules, one platform at a time. Everything here decides
// what ends up on someone's card, so everything here is worth an assertion; how
// the screen looks is judged in the previews.

@Suite("Contact values")
struct ContactValueTests {
    // Pasting the profile link is what people actually do, so the handle has to
    // survive every shape a share sheet hands over, tracking parameters and all.
    @Test("an Instagram handle survives every shape a link arrives in")
    func instagramFromLinks() {
        let expected = "tonybuilds"
        let inputs = [
            "tonybuilds",
            "@tonybuilds",
            "  tonybuilds  ",
            "instagram.com/tonybuilds",
            "https://instagram.com/tonybuilds",
            "https://www.instagram.com/tonybuilds/",
            "https://www.instagram.com/tonybuilds?igsh=MXY5cHo1",
            "https://www.instagram.com/tonybuilds/#reels",
            "HTTPS://INSTAGRAM.COM/tonybuilds",
        ]
        for input in inputs {
            #expect(ContactValue.instagramHandle(from: input) == expected, "\(input)")
        }
    }

    @Test("Instagram keeps the characters it allows and rejects the rest")
    func instagramCharacters() {
        #expect(ContactValue.instagramHandle(from: "tony.builds_01") == "tony.builds_01")
        #expect(ContactValue.instagramHandle(from: "") == nil)
        #expect(ContactValue.instagramHandle(from: "@") == nil)
        #expect(ContactValue.instagramHandle(from: "instagram.com/") == nil)
        #expect(ContactValue.instagramHandle(from: "tony builds") == nil)
        #expect(ContactValue.instagramHandle(from: "tony/builds") == "tony")
        // Instagram caps handles at 30, so anything longer came from somewhere
        // that is not a handle.
        #expect(ContactValue.instagramHandle(from: String(repeating: "a", count: 31)) == nil)
    }

    // X still answers to both of its addresses, and a link copied years ago is
    // still the link someone has.
    @Test("an X handle survives either of X's addresses")
    func xFromLinks() {
        let expected = "tonybuilds"
        let inputs = [
            "tonybuilds",
            "@tonybuilds",
            "x.com/tonybuilds",
            "https://x.com/tonybuilds",
            "https://twitter.com/tonybuilds/",
            "https://x.com/tonybuilds?s=21",
        ]
        for input in inputs {
            #expect(ContactValue.xHandle(from: input) == expected, "\(input)")
        }
    }

    @Test("X keeps the characters it allows and rejects the rest")
    func xCharacters() {
        #expect(ContactValue.xHandle(from: "tony_builds1") == "tony_builds1")
        #expect(ContactValue.xHandle(from: "") == nil)
        #expect(ContactValue.xHandle(from: "tony.builds") == nil)
        #expect(ContactValue.xHandle(from: "tony builds") == nil)
        // X caps handles at 15, so anything longer is not one.
        #expect(ContactValue.xHandle(from: String(repeating: "a", count: 16)) == nil)
    }

    // Only ever asked for by the add-someone sheet: the card offers four
    // platforms and Telegram is not one of them, but a person you save by hand
    // can carry any handle worth recording.
    @Test("a Telegram handle survives either of Telegram's addresses")
    func telegramFromLinks() {
        let expected = "tonybuilds"
        let inputs = [
            "tonybuilds",
            "@tonybuilds",
            "t.me/tonybuilds",
            "https://t.me/tonybuilds",
            "https://telegram.me/tonybuilds/",
            "  https://t.me/tonybuilds?start=1  ",
        ]
        for input in inputs {
            #expect(ContactValue.telegramHandle(from: input) == expected, "\(input)")
        }
    }

    @Test("Telegram keeps the characters and the lengths it allows")
    func telegramCharacters() {
        #expect(ContactValue.telegramHandle(from: "tony_builds1") == "tony_builds1")
        #expect(ContactValue.telegramHandle(from: "") == nil)
        #expect(ContactValue.telegramHandle(from: "tony.builds") == nil)
        #expect(ContactValue.telegramHandle(from: "tony-builds") == nil)
        // Telegram's own bounds: five to thirty-two.
        #expect(ContactValue.telegramHandle(from: "tony") == nil)
        #expect(ContactValue.telegramHandle(from: String(repeating: "a", count: 33)) == nil)
        #expect(ContactValue.telegramHandle(from: String(repeating: "a", count: 32)) != nil)
    }

    @Test("a LinkedIn address is reduced to the part that identifies the profile")
    func linkedInFromLinks() {
        let expected = "tony-nguyen"
        let inputs = [
            "tony-nguyen",
            "linkedin.com/in/tony-nguyen",
            "https://www.linkedin.com/in/tony-nguyen/",
            "https://linkedin.com/in/tony-nguyen?originalSubdomain=vn",
        ]
        for input in inputs {
            #expect(ContactValue.linkedInHandle(from: input) == expected, "\(input)")
        }
        #expect(ContactValue.linkedInHandle(from: "") == nil)
        #expect(ContactValue.linkedInHandle(from: "tony nguyen") == nil)
    }

    // The guess only has to be close. LinkedIn proves who someone is and never
    // sends their profile address, so the panel exists to be corrected.
    @Test("the LinkedIn guess turns a name into an address-shaped slug")
    func linkedInGuess() {
        #expect(ContactValue.linkedInSlug(from: "Tony Nguyen") == "tony-nguyen")
        #expect(ContactValue.linkedInSlug(from: "  Maya   Chen ") == "maya-chen")
        #expect(ContactValue.linkedInSlug(from: "Nguyen Minh Thien") == "nguyen-minh-thien")
        #expect(ContactValue.linkedInSlug(from: "O'Brien-Smith") == "o-brien-smith")
        #expect(ContactValue.linkedInSlug(from: "") == "")
    }

    // Diacritics have to fold rather than survive: a slug is an address, and an
    // address with an accent in it is not the one LinkedIn issued.
    @Test("the LinkedIn guess folds accents away")
    func linkedInGuessFoldsAccents() {
        #expect(ContactValue.linkedInSlug(from: "Nguyễn Minh Thiện") == "nguyen-minh-thien")
        #expect(ContactValue.linkedInSlug(from: "Zoë Müller") == "zoe-muller")
    }

    // Stored in the one form that means the same thing everywhere, because a
    // number written the way one country writes it is ambiguous in the next.
    // Every case here carries its own country code, so the result does not move
    // with whatever region the machine running the tests is set to.
    @Test("a phone number is stored in E.164 or not at all")
    func phoneNumbers() {
        #expect(ContactValue.phoneNumber(from: "+84 90 123 4567") == "+84901234567")
        #expect(ContactValue.phoneNumber(from: "+33 6 89 01 73 83") == "+33689017383")
        #expect(ContactValue.phoneNumber(from: "+44 20 7183 8750") == "+442071838750")

        #expect(ContactValue.phoneNumber(from: "") == nil)
        #expect(ContactValue.phoneNumber(from: "12") == nil)
        #expect(ContactValue.phoneNumber(from: "not a number") == nil)
    }
}
