import Foundation
import Testing
@testable import Haven

// What each row of the edit screen reads, and which star it points at. The
// mapping is the whole reason an unlit star is legible, so it is asserted
// rather than trusted.

@Suite("My card fields")
struct MyCardFieldTests {
    @Test("every field owns the star the plan fixed")
    func slots() {
        #expect(CardField.name.slot == .name)
        #expect(CardField.city.slot == .city)
        #expect(CardField.handles.slot == .primaryContact)
        #expect(CardField.photo.slot == .photo)
        #expect(CardField.company.slot == .company)
        #expect(CardField.role.slot == .role)
        // One row per star, and no star without a row: an unlit star nobody
        // can act on would be a nudge pointing at nothing.
        #expect(Set(CardField.allCases.map(\.slot)) == Set(StarSlot.allCases))
    }

    // A row reads nil when its field is empty, which is what makes it show the
    // placeholder and say "empty" to a screen reader.
    @Test("an empty field has no value to show")
    func emptyValues() {
        let bare = MyCard(username: "maya")
        for field in CardField.allCases {
            #expect(bare.value(for: field) == nil, "\(field.title) should read as empty")
        }

        // A field the server stored blank is empty too, not a blank line.
        let blank = MyCard(username: "maya", name: "", company: "", role: "")
        #expect(blank.value(for: .name) == nil)
        #expect(blank.value(for: .company) == nil)
        #expect(blank.value(for: .role) == nil)

        // So is a handle list that exists and holds nothing.
        var noHandles = MyCard(username: "maya")
        noHandles.handles = []
        #expect(noHandles.value(for: .handles) == nil)
    }

    @Test("a filled field reads back what is in it")
    func filledValues() {
        var card = MyCard(username: "maya", name: "Maya Chen")
        card.city = MyCard.City(name: "Ho Chi Minh City", country: "Vietnam")
        card.company = "Haven"
        card.role = "Founder"
        card.photoStorageId = "kg700xyz"
        card.handles = [MyCard.Handle(platform: .x, value: "mayachen", verified: true)]

        #expect(card.value(for: .name) == "Maya Chen")
        #expect(card.value(for: .city) == "Ho Chi Minh City, Vietnam")
        #expect(card.value(for: .company) == "Haven")
        #expect(card.value(for: .role) == "Founder")
        #expect(card.value(for: .photo) != nil)
        // One way to be reached shows the address itself; more than one is a
        // count, because listing four of them in a row is a list, not a line.
        #expect(card.value(for: .handles) == "x.com/mayachen")

        card.handles?.append(MyCard.Handle(platform: .phone, value: "+84900000000", verified: false))
        #expect(card.value(for: .handles) == "2 ways")
    }

    // Only the fields that are literally one string share the text editor. A
    // key here for city or handles would write the wrong shape to the server.
    @Test("only the plain text fields carry a stored key")
    func storedKeys() {
        #expect(CardField.name.storedKey == "name")
        #expect(CardField.company.storedKey == "company")
        #expect(CardField.role.storedKey == "role")
        #expect(CardField.city.storedKey == nil)
        #expect(CardField.handles.storedKey == nil)
        #expect(CardField.photo.storedKey == nil)
    }
}
