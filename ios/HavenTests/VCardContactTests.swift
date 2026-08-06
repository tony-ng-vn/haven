import Foundation
import Testing
@testable import Haven

// vCard 3.0, because that is what Contacts itself exports and
// CNContactVCardSerialization is unreliable on 4.0 -- see VCardContact.swift.

private let mai = """
    BEGIN:VCARD
    VERSION:3.0
    N:Tr\u{e2}n;Mai;;;
    FN:Mai Tr\u{e2}n
    TEL;TYPE=CELL:+84 90 123 4567
    EMAIL;TYPE=INTERNET:mai@example.com
    END:VCARD
    """

private let phoneOnly = """
    BEGIN:VCARD
    VERSION:3.0
    N:Nguyen;Tony;;;
    FN:Tony Nguyen
    TEL;TYPE=CELL:+1 415 555 0132
    END:VCARD
    """

private let emailOnly = """
    BEGIN:VCARD
    VERSION:3.0
    N:Le;Anh;;;
    FN:Anh Le
    EMAIL;TYPE=INTERNET:anh@example.com
    END:VCARD
    """

private let orgOnly = """
    BEGIN:VCARD
    VERSION:3.0
    ORG:Haven Studio
    TEL;TYPE=WORK:+1 415 555 0100
    END:VCARD
    """

private let nameOnlyNoHandle = """
    BEGIN:VCARD
    VERSION:3.0
    N:Pham;Linh;;;
    FN:Linh Pham
    END:VCARD
    """

@Suite("Reading a shared contact card")
struct VCardContactTests {
    @Test("a card with a name, a phone and an email reads all three")
    func fullCard() {
        let parsed = VCardContact.parse(Data(mai.utf8))
        #expect(parsed?.name == "Mai Tr\u{e2}n")
        #expect(parsed?.phone == "+84 90 123 4567")
        #expect(parsed?.email == "mai@example.com")
    }

    @Test("a card with only a phone reads a nil email")
    func phoneOnlyCard() {
        let parsed = VCardContact.parse(Data(phoneOnly.utf8))
        #expect(parsed?.name == "Tony Nguyen")
        #expect(parsed?.phone == "+1 415 555 0132")
        #expect(parsed?.email == nil)
    }

    @Test("a card with only an email reads a nil phone")
    func emailOnlyCard() {
        let parsed = VCardContact.parse(Data(emailOnly.utf8))
        #expect(parsed?.name == "Anh Le")
        #expect(parsed?.phone == nil)
        #expect(parsed?.email == "anh@example.com")
    }

    // A business card with no N or FN field still names somebody -- the
    // organization is what a person handed over on purpose.
    @Test("a card with no personal name falls back to the organization")
    func orgOnlyCard() {
        let parsed = VCardContact.parse(Data(orgOnly.utf8))
        #expect(parsed?.name == "Haven Studio")
        #expect(parsed?.phone == "+1 415 555 0100")
    }

    // VCardContact only ever refuses a card that names nobody; a name with no
    // way to reach them is still a name, and it is ShareSubject's job to
    // decide that is not enough to save.
    @Test("a name with neither a phone nor an email still reads the name")
    func nameOnly() {
        let parsed = VCardContact.parse(Data(nameOnlyNoHandle.utf8))
        #expect(parsed?.name == "Linh Pham")
        #expect(parsed?.phone == nil)
        #expect(parsed?.email == nil)
    }

    @Test("a card naming nobody at all does not parse")
    func nothingToName() {
        let blank = """
            BEGIN:VCARD
            VERSION:3.0
            TEL;TYPE=CELL:+1 415 555 0100
            END:VCARD
            """
        #expect(VCardContact.parse(Data(blank.utf8)) == nil)
    }

    @Test("data that is not a vCard at all does not parse")
    func notAVCard() {
        #expect(VCardContact.parse(Data("hello".utf8)) == nil)
        #expect(VCardContact.parse(Data()) == nil)
    }
}

@Suite("What a shared contact card becomes")
struct ShareSubjectContactTests {
    // A phone is the stronger key: it changes less often and is less likely
    // to be entered two different ways by two different apps than an email.
    @Test("a card with both a phone and an email is keyed on the phone")
    func phoneWinsOverEmail() {
        #expect(
            ShareSubject(vCard: Data(mai.utf8))
                == .contact(name: "Mai Tr\u{e2}n", platform: "phone", handleValue: "+84 90 123 4567")
        )
    }

    @Test("a card with only an email is keyed on the email")
    func emailWhenNoPhone() {
        #expect(
            ShareSubject(vCard: Data(emailOnly.utf8))
                == .contact(name: "Anh Le", platform: "email", handleValue: "anh@example.com")
        )
    }

    // saveSharedProfile dedups on a handle. A name with neither a phone nor
    // an email can never drain, so it is not a subject at all -- the same
    // "not one person's profile" dead end an unrecognized URL already hits.
    @Test("a card with a name but no phone and no email is not a subject")
    func nameWithNoHandle() {
        #expect(ShareSubject(vCard: Data(nameOnlyNoHandle.utf8)) == nil)
    }

    @Test("data that is not a vCard is not a subject")
    func garbageIsNotASubject() {
        #expect(ShareSubject(vCard: Data("not a vcard".utf8)) == nil)
    }
}
