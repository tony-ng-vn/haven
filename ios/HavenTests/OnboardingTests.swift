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

// Which sky the reveal draws: the permanent one, seeded from the handle My
// Card, Connect and the public web card all already draw from, not the
// userId-seeded one the questions were shown with.
@Suite("Reveal sky seed")
struct RevealSkySeedTests {
    @Test("the reveal seeds from the handle once there is one")
    func seedsFromHandle() {
        #expect(RevealSky.seed(username: "mayachen", userId: "user_2abcDEF") == "mayachen")
    }

    // Not actually reachable through `MyCard.username`, which is not
    // optional, but the fallback is what stops an empty handle from ever
    // drawing an empty figure or crashing the reveal.
    @Test("an empty handle falls back to the seed the questions used")
    func fallsBackToUserId() {
        #expect(RevealSky.seed(username: "", userId: "user_2abcDEF") == "user_2abcDEF")
    }
}

// The one rule `OnboardingModel.importAvatar` cannot skip: a photo somebody
// chose is never replaced by one a connection merely proved.
@Suite("Avatar import")
struct AvatarImportTests {
    @Test("a card with no photo yet is worth importing into")
    func noPhotoYet() {
        #expect(AvatarImport.shouldReplace(MyCard(username: "maya")) == true)
    }

    @Test("a card that already has a photo is never overwritten")
    func alreadyHasPhoto() {
        var card = MyCard(username: "maya")
        card.photoStorageId = "storage_abc123"
        #expect(AvatarImport.shouldReplace(card) == false)
    }

    // Not reachable through the real call path -- `saveContact` always sets
    // `card` before `importAvatar` runs -- but nil is not "unknown, so try
    // it": with nowhere yet to attach a photo, this stays a no like an
    // existing one does, not a yes like an empty card would suggest.
    @Test("no card yet is not imported into either")
    func noCardYet() {
        #expect(AvatarImport.shouldReplace(nil) == false)
    }
}

// The server's record of what happened to each question, and how it meets the
// device store that used to be the only one.
@Suite("Onboarding progress, recorded")
struct OnboardingProgressTests {
    private func card(_ onboarding: MyCard.Onboarding?) -> MyCard {
        var card = MyCard(username: "maya", name: "Maya Chen")
        card.onboarding = onboarding
        return card
    }

    // The reinstall case, which is the whole point of the record. A skip made
    // on the last phone is honoured on this one, with an empty device store.
    @Test("a skip recorded on the server is honoured on a fresh device")
    func serverSkipSurvivesReinstall() {
        let recorded = card(MyCard.Onboarding(location: .skipped))
        #expect(OnboardingProgress.skipped(in: recorded, onDevice: []) == [.location])
        #expect(OnboardingStep.first(unansweredIn: recorded, skipped: [.location]) == .contact)
    }

    // The other direction: a skip made with no signal is still a skip, even
    // though the server never heard about it.
    @Test("a skip the server has not heard about still counts")
    func deviceSkipCountsAlone() {
        #expect(OnboardingProgress.skipped(in: card(nil), onDevice: [.contact]) == [.contact])
        let recorded = card(MyCard.Onboarding(location: .skipped))
        #expect(
            OnboardingProgress.skipped(in: recorded, onDevice: [.contact])
                == [.location, .contact]
        )
    }

    // Only skips. An answered question is already covered by the field it
    // fills, and counting it here would keep the question unasked after
    // somebody cleared that field.
    @Test("an answered question is not a skipped one")
    func answeredIsNotSkipped() {
        let answered = card(MyCard.Onboarding(name: .answered, location: .answered))
        #expect(OnboardingProgress.skipped(in: answered, onDevice: []).isEmpty)
    }

    @Test("the server is told about skips it does not have")
    func pushesUnrecorded() {
        #expect(OnboardingProgress.unrecorded(onDevice: [.location], in: card(nil)) == [.location])
        // Already recorded, however it was recorded: nothing to say.
        let recorded = card(MyCard.Onboarding(location: .skipped))
        #expect(OnboardingProgress.unrecorded(onDevice: [.location], in: recorded).isEmpty)
        let answeredInstead = card(MyCard.Onboarding(location: .answered))
        #expect(OnboardingProgress.unrecorded(onDevice: [.location], in: answeredInstead).isEmpty)
    }

    // The server refuses to record a skipped name, so sending one would be an
    // error repeated on every launch for the life of the install.
    @Test("a skipped name is never pushed")
    func neverPushesName() {
        #expect(OnboardingProgress.unrecorded(onDevice: [.name, .contact], in: card(nil)) == [.contact])
    }

    @Test("what is pushed goes in question order")
    func pushesInOrder() {
        #expect(
            OnboardingProgress.unrecorded(onDevice: [.contact, .location], in: card(nil))
                == [.location, .contact]
        )
    }

    // Onboarding happening once is a fact the server holds now. Before this,
    // clearing your city on My Card dropped you back into the questions,
    // because an empty field and an unasked question looked identical.
    @Test("a finished onboarding does not restart when a field is cleared")
    func completedStaysCompleted() {
        var finished = card(
            MyCard.Onboarding(
                name: .answered,
                location: .answered,
                contact: .answered,
                completedAt: 1_700_000_000_000
            )
        )
        // Every field but the name emptied, exactly as clearing them on My Card
        // would leave the card.
        finished.city = nil
        finished.handles = []
        #expect(OnboardingStep.first(unansweredIn: finished) == nil)
    }

    // A row written before the record existed carries none of it, and has to
    // behave exactly as it did.
    @Test("a card with no record behaves the way it always did")
    func legacyCardUnchanged() {
        #expect(OnboardingStep.first(unansweredIn: card(nil)) == .location)
        #expect(OnboardingProgress.skipped(in: card(nil), onDevice: []).isEmpty)
    }
}
