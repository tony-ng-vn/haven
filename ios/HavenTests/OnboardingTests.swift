import Foundation
import Testing
@testable import Haven

// Where onboarding resumes, and which stars a card has earned. Both are decided
// from the card alone, so both are plain functions and both are tested here.
// What the screens look like is judged in the previews and on a device.

private func decode(_ json: String) throws -> MyCard? {
    try JSONDecoder().decode(MyCard?.self, from: Data(json.utf8))
}

@Suite("Onboarding")
struct OnboardingTests {
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

    @Test("the flow resumes at the first unanswered question")
    func resume() {
        #expect(OnboardingStep.first(unansweredIn: nil) == .name)
        #expect(OnboardingStep.first(unansweredIn: MyCard(username: "maya")) == .name)

        let named = MyCard(username: "maya", name: "Maya Chen")
        #expect(OnboardingStep.first(unansweredIn: named) == .location)

        var located = named
        located.city = MyCard.City(name: "Ho Chi Minh City")
        #expect(OnboardingStep.first(unansweredIn: located) == .contact)

        var reachable = located
        reachable.handles = [MyCard.Handle(platform: .x, value: "mayachen", verified: true)]
        #expect(OnboardingStep.first(unansweredIn: reachable) == nil)
    }

    // Fields answered out of order must not skip the ones still owed. Company
    // and role are never asked in onboarding, so they cannot end it either.
    @Test("a field answered later does not skip an earlier question")
    func outOfOrder() {
        var card = MyCard(username: "maya")
        card.city = MyCard.City(name: "Ho Chi Minh City")
        card.company = "Haven"
        card.handles = [MyCard.Handle(platform: .phone, value: "+84900000000", verified: false)]

        #expect(OnboardingStep.first(unansweredIn: card) == .name)
    }
}
