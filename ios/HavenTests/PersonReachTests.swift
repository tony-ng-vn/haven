import Foundation
import Testing
@testable import Haven

@Suite("Reaching a saved person")
struct PersonReachTests {
    // The fourth stroke of the loop: a tap has to land in the app they are
    // actually in, not on a page about them.
    @Test("a handle on a platform Haven knows opens that platform")
    func opensKnownPlatforms() {
        #expect(
            PersonReach.url(platform: "instagram", value: "mai.makes")?.absoluteString
                == "https://instagram.com/mai.makes"
        )
        #expect(
            PersonReach.url(platform: "linkedin", value: "mai-tran-8a91b2")?.absoluteString
                == "https://linkedin.com/in/mai-tran-8a91b2"
        )
        #expect(
            PersonReach.url(platform: "telegram", value: "mai_makes")?.absoluteString
                == "https://t.me/mai_makes"
        )
    }

    // Rows written before the rename still say twitter, and the person behind
    // them has not moved.
    @Test("a twitter handle opens X")
    func twitterIsX() {
        #expect(
            PersonReach.url(platform: "twitter", value: "mai_makes")?.absoluteString
                == "https://x.com/mai_makes"
        )
        #expect(PersonReach.label("twitter") == "X")
    }

    // A number is dialled rather than browsed, and the spaces somebody stored
    // it with are not part of the number.
    @Test("a phone number becomes a call")
    func phoneDials() {
        #expect(
            PersonReach.url(platform: "phone", value: "+84 90 123 4567")?.absoluteString
                == "tel:+84901234567"
        )
        #expect(
            PersonReach.url(platform: "whatsapp", value: "+84901234567")?.absoluteString
                == "https://wa.me/84901234567"
        )
    }

    // The honest miss. A platform Haven has never heard of is still a real way
    // to reach somebody, so it shows -- it just does not promise a tap.
    @Test("an unknown platform has nowhere to open and says so")
    func unknownPlatform() {
        #expect(PersonReach.url(platform: "signal", value: "mai.99") == nil)
        #expect(PersonReach.display(platform: "signal", value: "mai.99") == "mai.99")
        #expect(PersonReach.label("signal") == "signal")
    }

    @Test("a blank handle opens nothing")
    func blankHandle() {
        #expect(PersonReach.url(platform: "instagram", value: "   ") == nil)
        #expect(PersonReach.url(platform: "phone", value: "abc") == nil)
    }

    // Platform names arrive folded from the server, but a row written before
    // that folding existed can still carry "Instagram ".
    @Test("a platform name is folded before it is recognised")
    func foldsPlatformNames() {
        #expect(
            PersonReach.url(platform: " Instagram ", value: "mai.makes")?.absoluteString
                == "https://instagram.com/mai.makes"
        )
    }

    @Test("a handle reads as the address it points at, or as itself")
    func display() {
        #expect(
            PersonReach.display(platform: "instagram", value: "mai.makes")
                == "instagram.com/mai.makes"
        )
        #expect(PersonReach.display(platform: "phone", value: "+84901234567") == "+84901234567")
    }

    // The offered list is longer than the four your own card carries, which is
    // the asymmetry mvp-design names.
    @Test("the offered platforms include the ones only a saved person can have")
    func offerable() {
        #expect(PersonReach.offerable.contains("whatsapp"))
        #expect(PersonReach.offerable.contains("telegram"))
        // The old name for X is readable but never offered.
        #expect(!PersonReach.offerable.contains("twitter"))
    }

    @Test("a typed handle is parsed by its platform's own rules")
    func parsing() {
        #expect(PersonReach.parse(platform: "instagram", from: "instagram.com/mai.makes") == "mai.makes")
        #expect(PersonReach.parse(platform: "x", from: "@mai_makes") == "mai_makes")
        #expect(PersonReach.parse(platform: "phone", from: "+84 90 123 4567") == "+84901234567")
        #expect(PersonReach.parse(platform: "instagram", from: "not a handle!") == nil)
        // A platform with no rules Haven knows keeps what was typed rather than
        // refusing it under a rule Haven does not have.
        #expect(PersonReach.parse(platform: "signal", from: "  mai.99  ") == "mai.99")
        #expect(PersonReach.parse(platform: "signal", from: "   ") == nil)
    }
}

// A handle rename breaks a link built from the handle -- these are the two
// platforms with an id worth building a rename-proof link from.
@Suite("Reaching a saved person by their platform id")
struct PersonReachPlatformIdTests {
    // X's own recommendation: a link built from the numeric id keeps working
    // after the account renames, where a link built from the handle breaks.
    @Test("an X handle with a resolved id opens the id-based link")
    func xWithId() {
        #expect(
            PersonReach.url(platform: "x", value: "mai_makes", platformId: "1477479148")?
                .absoluteString == "https://x.com/intent/user?user_id=1477479148"
        )
        // twitter is the same platform under its old name.
        #expect(
            PersonReach.url(platform: "twitter", value: "mai_makes", platformId: "1477479148")?
                .absoluteString == "https://x.com/intent/user?user_id=1477479148"
        )
    }

    @Test("an X handle with no resolved id falls back to the handle link")
    func xWithoutId() {
        #expect(
            PersonReach.url(platform: "x", value: "mai_makes", platformId: nil)?.absoluteString
                == "https://x.com/mai_makes"
        )
        #expect(
            PersonReach.url(platform: "x", value: "mai_makes", platformId: "   ")?.absoluteString
                == "https://x.com/mai_makes"
        )
    }

    @Test("linkedin ignores a platformId entirely -- it never carries one")
    func linkedInUntouched() {
        #expect(
            PersonReach.url(platform: "linkedin", value: "mai-tran-8a91b2", platformId: "999")?
                .absoluteString == "https://linkedin.com/in/mai-tran-8a91b2"
        )
    }

    @Test("instagram's plain url is always the web address, id or not")
    func instagramURLIsAlwaysWeb() {
        #expect(
            PersonReach.url(platform: "instagram", value: "mai.makes", platformId: "17841")?
                .absoluteString == "https://instagram.com/mai.makes"
        )
    }

    @Test("instagram's app deep link needs a non-blank id")
    func instagramAppURL() {
        #expect(
            PersonReach.instagramAppURL(platformId: "17841")?.absoluteString
                == "instagram://user?id=17841"
        )
        #expect(PersonReach.instagramAppURL(platformId: "   ") == nil)
    }

    // The decision itself, not whether Instagram happens to be installed on
    // whatever machine ran the test -- `canOpenAppURL` is what is pinned.
    @Test("instagram opens the app when it is installed and there is an id")
    func opensAppWhenInstalled() {
        let opened = PersonReach.openURL(
            platform: "instagram", value: "mai.makes", platformId: "17841",
            canOpenAppURL: { _ in true }
        )
        #expect(opened?.absoluteString == "instagram://user?id=17841")
    }

    @Test("instagram falls back to the web url when the app cannot open it")
    func fallsBackWhenNotInstalled() {
        let opened = PersonReach.openURL(
            platform: "instagram", value: "mai.makes", platformId: "17841",
            canOpenAppURL: { _ in false }
        )
        #expect(opened?.absoluteString == "https://instagram.com/mai.makes")
    }

    @Test("instagram falls back to the web url when there is no id to link with")
    func fallsBackWithNoId() {
        let opened = PersonReach.openURL(
            platform: "instagram", value: "mai.makes", platformId: nil,
            canOpenAppURL: { _ in true }
        )
        #expect(opened?.absoluteString == "https://instagram.com/mai.makes")
    }

    // A platform other than Instagram never even asks `canOpenAppURL` --
    // there is no app deep link for it to try.
    @Test("openURL only asks canOpenAppURL for Instagram")
    func onlyAsksForInstagram() {
        var asked = false
        _ = PersonReach.openURL(
            platform: "x", value: "mai_makes", platformId: "1477479148",
            canOpenAppURL: { _ in
                asked = true
                return true
            }
        )
        #expect(!asked)
    }
}
