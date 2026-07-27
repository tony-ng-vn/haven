import Foundation
import Testing
@testable import Haven

// The card as the server sends it, and which stars it has earned. Both are
// decided from the card alone, so both are plain functions and both are tested
// here. What the card looks like is judged in the previews and on a device.

private func decode(_ json: String) throws -> MyCard? {
    try JSONDecoder().decode(MyCard?.self, from: Data(json.utf8))
}

@Suite("My card")
struct MyCardTests {
    // The exact shape myCardValidator returns, including the two keys the app
    // has no use for and the stored city's private Phase 3 filter key. An
    // unknown key must stay harmless: the server is free to add fields.
    @Test("a card decodes what profiles:getMyCard returns")
    func decodesCard() throws {
        let card = try #require(
            try decode(
                """
                {
                  "_id": "j5700abc",
                  "_creationTime": 1730000000000.5,
                  "updatedAt": 1730000000001.5,
                  "username": "maya",
                  "name": "Maya Chen",
                  "city": {
                    "name": "Ho Chi Minh City",
                    "country": "Vietnam",
                    "normalized": "ho chi minh city"
                  },
                  "handles": [
                    { "platform": "x", "value": "mayachen", "verified": true }
                  ],
                  "primaryPlatform": "x"
                }
                """
            )
        )

        #expect(card.username == "maya")
        #expect(card.name == "Maya Chen")
        #expect(card.city?.name == "Ho Chi Minh City")
        #expect(card.city?.admin == nil)
        #expect(card.handles == [MyCard.Handle(platform: .x, value: "mayachen", verified: true)])
        #expect(card.primaryPlatform == .x)
    }

    @Test("no profile row yet decodes as no card")
    func decodesNull() throws {
        #expect(try decode("null") == nil)
    }

    // A storage id is not something the app can fetch, so the server resolves
    // it. Without this the photo uploads, the row says it is there, and the
    // card face never changes.
    @Test("a photo arrives as a url the app can fetch")
    func decodesPhotoURL() throws {
        let card = try #require(
            try decode(
                """
                {
                  "username": "maya",
                  "name": "Maya Chen",
                  "photoStorageId": "kg700xyz",
                  "photoUrl": "https://example.convex.cloud/api/storage/kg700xyz"
                }
                """
            )
        )

        #expect(card.photoURL == URL(string: "https://example.convex.cloud/api/storage/kg700xyz"))
    }

    // Null, not absent: the app has to tell "no photo" from "not loaded yet".
    @Test("no photo decodes as no url")
    func decodesMissingPhotoURL() throws {
        let card = try #require(
            try decode(#"{ "username": "maya", "photoUrl": null }"#)
        )

        #expect(card.photoURL == nil)
    }

    @Test("each field lights its own fixed star")
    func filledSlots() {
        #expect(MyCard(username: "maya").filledSlots.isEmpty)

        let named = MyCard(username: "maya", name: "Maya Chen")
        #expect(named.filledSlots == [.name])

        let full = MyCard(
            username: "maya",
            name: "Maya Chen",
            photoStorageId: "kg700xyz",
            city: MyCard.City(name: "Ho Chi Minh City"),
            handles: [MyCard.Handle(platform: .x, value: "mayachen", verified: true)],
            primaryPlatform: .x,
            company: "Haven",
            role: "Founder"
        )
        #expect(full.filledSlots == Set(StarSlot.allCases))
    }

    // A name the server would refuse is not an answer, so the flow must not
    // treat it as one and walk past the question.
    @Test("a blank name leaves the name star unlit")
    func blankName() {
        #expect(MyCard(username: "maya", name: "").filledSlots.isEmpty)
    }

    // An empty list means the contact question was reached and answered with
    // nothing, which is not an answer.
    @Test("an empty handle list leaves the contact star unlit")
    func emptyHandles() {
        #expect(MyCard(username: "maya", handles: []).filledSlots.isEmpty)
    }
}

// MARK: - Display

@Suite("Card display")
struct MyCardDisplayTests {
    // Every platform shows as the address it points at, because a bare
    // "@mayachen" reads the same for X and for Instagram and the card has no
    // glyph to tell them apart.
    @Test("a handle shows as the address it points at")
    func handleDisplay() {
        func display(_ platform: MyCard.Platform, _ value: String) -> String {
            MyCard.Handle(platform: platform, value: value, verified: false).display
        }

        #expect(display(.x, "mayachen") == "x.com/mayachen")
        #expect(display(.instagram, "mayachen") == "instagram.com/mayachen")
        #expect(display(.linkedin, "maya-chen") == "linkedin.com/in/maya-chen")
        // A number is already an address of its own, and prefixing it would
        // invent one that does not exist.
        #expect(display(.phone, "+84 90 000 0000") == "+84 90 000 0000")
    }

    // The prefixes are what a link to the person is built from, so a wrong one
    // is a link to the wrong place rather than a cosmetic slip.
    @Test("every platform knows what its addresses start with")
    func addressPrefixes() {
        #expect(MyCard.Platform.x.addressPrefix == "x.com/")
        #expect(MyCard.Platform.instagram.addressPrefix == "instagram.com/")
        #expect(MyCard.Platform.linkedin.addressPrefix == "linkedin.com/in/")
        #expect(MyCard.Platform.phone.addressPrefix.isEmpty)
    }

    @Test("a city line shows the parts it has and nothing else")
    func cityLine() {
        #expect(MyCard.City(name: "Ho Chi Minh City").line == "Ho Chi Minh City")
        #expect(
            MyCard.City(name: "Austin", admin: "TX", country: "United States").line
                == "Austin, TX, United States"
        )
        #expect(
            MyCard.City(name: "Ho Chi Minh City", country: "Vietnam").line
                == "Ho Chi Minh City, Vietnam"
        )
        // A country with no states comes back from MapKit with a blank admin
        // area, which as a raw join would render as a stray comma.
        #expect(
            MyCard.City(name: "Singapore", admin: "", country: "Singapore").line
                == "Singapore, Singapore"
        )
    }

    @Test("the card leads with the handle the person chose")
    func primaryHandle() {
        let x = MyCard.Handle(platform: .x, value: "mayachen", verified: true)
        let phone = MyCard.Handle(platform: .phone, value: "+84900000000", verified: false)

        var card = MyCard(username: "maya", handles: [phone, x], primaryPlatform: .x)
        #expect(card.primaryHandle == x)

        // No choice recorded yet: the only handle there is still beats none.
        card.primaryPlatform = nil
        #expect(card.primaryHandle == phone)

        // A choice whose handle is gone must not silently show nothing either.
        card.handles = [phone]
        card.primaryPlatform = .x
        #expect(card.primaryHandle == phone)

        card.handles = []
        #expect(card.primaryHandle == nil)
        #expect(MyCard(username: "maya").primaryHandle == nil)
    }
}
