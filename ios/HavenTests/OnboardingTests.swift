import Foundation
import Testing
@testable import Haven

// Where onboarding resumes, and what it remembers about questions that were
// passed on. Both are decided from the card and the local skip store alone, so
// both are plain functions. What the screens look like is judged in the
// previews and on a device. The card type itself is tested in `MyCardTests`.

@Suite("Onboarding")
struct OnboardingTests {
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

    // Skipping is the whole reason the skip set exists: without it the flow
    // hands back the question the person just declined, forever.
    @Test("a skipped question is not asked again")
    func skipping() {
        let named = MyCard(username: "maya", name: "Maya Chen")

        #expect(OnboardingStep.first(unansweredIn: named, skipped: [.location]) == .contact)
        #expect(OnboardingStep.first(unansweredIn: named, skipped: [.location, .contact]) == nil)
    }

    // Skipping the contact question does not excuse the city question above it.
    @Test("skipping a later question does not skip an earlier one")
    func skippingOutOfOrder() {
        let named = MyCard(username: "maya", name: "Maya Chen")

        #expect(OnboardingStep.first(unansweredIn: named, skipped: [.contact]) == .location)
    }

    // Name is the one required answer, so nothing offers to skip it and a
    // stored skip for it must not be honoured either.
    @Test("the name question cannot be skipped")
    func nameIsNotSkippable() {
        #expect(OnboardingStep.first(unansweredIn: nil, skipped: [.name, .location]) == .name)
    }

    // Answering beats skipping: a city that arrives later, from an edit or
    // another device, ends the question whatever the device remembers.
    @Test("an answer overrides a skip")
    func answerOverridesSkip() {
        var card = MyCard(username: "maya", name: "Maya Chen")
        card.city = MyCard.City(name: "Ho Chi Minh City")
        card.handles = [MyCard.Handle(platform: .x, value: "mayachen", verified: true)]

        #expect(OnboardingStep.first(unansweredIn: card, skipped: [.location]) == nil)
    }

    @Test("a city sends only the parts it has")
    func cityArgument() {
        let bare = CityInput(name: "Ho Chi Minh City").presentFields
        #expect(bare.keys.sorted() == ["name"])

        let full = CityInput(name: "Austin", admin: "TX", country: "United States")
            .presentFields
        #expect(full.keys.sorted() == ["admin", "country", "name"])

        // MapKit hands back an empty string for an admin area a country does not
        // have. Sent as-is that is a blank the server would store and the card
        // would render.
        let blankAdmin = CityInput(name: "Singapore", admin: "", country: "Singapore")
            .presentFields
        #expect(blankAdmin.keys.sorted() == ["country", "name"])
    }

    // The skip store is what decides whether someone is asked a question a
    // second time, so its round trip through UserDefaults is worth an assertion
    // rather than a hope. Each case uses its own user id, because the store is
    // shared with whatever else has run, and clears it first, because
    // UserDefaults outlives the run: the app stays installed on the simulator,
    // so without this the second run reads the first run's answer.
    @Test("a skip survives the app being killed")
    func skipsRoundTrip() {
        let userId = "user_skips_round_trip"
        OnboardingSkips.save([], userId: userId)
        #expect(OnboardingSkips.load(userId: userId).isEmpty)

        OnboardingSkips.save([.location, .contact], userId: userId)

        #expect(OnboardingSkips.load(userId: userId) == [.location, .contact])
    }

    // Two accounts on one phone is the case this guards: inheriting the last
    // person's skips would walk a new arrival straight past questions nobody
    // ever asked them.
    @Test("skips do not carry across accounts")
    func skipsAreKeyedByUser() {
        let mine = "user_skips_mine"
        let theirs = "user_skips_theirs"
        OnboardingSkips.save([], userId: theirs)

        OnboardingSkips.save([.location], userId: mine)

        #expect(OnboardingSkips.load(userId: theirs).isEmpty)
        #expect(OnboardingSkips.load(userId: mine) == [.location])
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
