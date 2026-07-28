import Foundation
import Testing
@testable import Haven

// MARK: - Cross-language agreement

@Suite("Profile URLs parse the same way the server does")
struct ProfileURLCrossLanguageTests {
    @Test("every URL normalizes to what normalizeUrl returns")
    func normalizeMatchesTypeScript() {
        for (input, want) in normalizeUrlCases {
            #expect(
                ProfileURL.normalize(input) == want,
                "normalize(\(input)): got \(String(describing: ProfileURL.normalize(input))), want \(String(describing: want))"
            )
        }
    }

    @Test("every URL parses to the same person the server would key on")
    func parseMatchesTypeScript() {
        for (input, want) in parseProfileUrlCases {
            #expect(
                ProfileURL.parse(input) == want,
                "parse(\(input)): got \(String(describing: ProfileURL.parse(input))), want \(String(describing: want))"
            )
        }
    }

    @Test("every slug guesses the same name")
    func nameGuessMatchesTypeScript() {
        for (slug, want) in nameGuessCases {
            #expect(
                ProfileURL.nameGuess(fromSlug: slug) == want,
                "nameGuess(\(slug)): got \(ProfileURL.nameGuess(fromSlug: slug)), want \(want)"
            )
        }
    }
}

// MARK: - What the ports have to get right on their own

@Suite("Profile URL parsing")
struct ProfileURLTests {
    // The three payloads captured from the real apps on 2026-07-27. Pinned
    // separately from the generated block because these are the only inputs
    // this feature is guaranteed to see, and a regression here is the feature
    // not working rather than a contract drifting.
    @Test("the payloads the three apps actually hand over")
    func realSharePayloads() {
        #expect(
            ProfileURL.parse("x.com/mai_makes?s=11")
                == ProfileLink(platform: .x, handle: "mai_makes")
        )
        #expect(
            ProfileURL.parse(
                "https://www.linkedin.com/in/mai-tran-8a91b2?utm_source=share_via&utm_content=profile&utm_medium=member_ios"
            ) == ProfileLink(platform: .linkedin, handle: "mai-tran-8a91b2")
        )
        #expect(
            ProfileURL.parse("https://www.instagram.com/mai.makes/?igsh=MXc4b2k5")
                == ProfileLink(platform: .instagram, handle: "mai.makes")
        )
    }

    // X shares without a scheme, so a parser that only accepted absolute URLs
    // would reject the one platform that shares most often.
    @Test("a URL with no scheme is still a profile")
    func schemeless() {
        #expect(
            ProfileURL.parse("instagram.com/mai.makes")
                == ProfileLink(platform: .instagram, handle: "mai.makes")
        )
    }

    // Foundation does not lowercase a host and JS URL does, so a share from an
    // app that capitalizes anything would land on a different platform (none).
    @Test("host case never decides the platform")
    func hostCase() {
        for host in ["INSTAGRAM.COM", "Instagram.com", "WWW.instagram.COM"] {
            #expect(
                ProfileURL.parse("https://\(host)/mai.makes")
                    == ProfileLink(platform: .instagram, handle: "mai.makes"),
                "\(host)"
            )
        }
    }

    // A host that merely ends in the letters of a profile domain belongs to a
    // stranger, and a share from one must never become a person.
    @Test("only a dot boundary makes a host ours")
    func hostSuffix() {
        #expect(ProfileURL.parse("https://notinstagram.com/mai") == nil)
        #expect(ProfileURL.parse("https://instagram.com.evil.example/mai") == nil)
        #expect(ProfileURL.parse("https://evil.example/instagram.com/mai") == nil)
    }

    // The one that cannot be caught by reading the code: Foundation's URL.path
    // is already decoded, so an encoded slash would silently become a path
    // separator and a check against a second segment would never run.
    @Test("an encoded slash is not a path separator")
    func encodedSlash() {
        #expect(ProfileURL.parse("https://instagram.com/mai%2Fmakes") == nil)
        #expect(ProfileURL.parse("https://x.com/mai_makes/%73tatus/17999") == nil)
    }

    @Test("a leading @ is stripped however many there are")
    func leadingAt() {
        #expect(
            ProfileURL.parse("https://x.com/@@MaiMakes")
                == ProfileLink(platform: .x, handle: "MaiMakes")
        )
        #expect(ProfileURL.parse("https://x.com/@@@") == nil)
    }
}

@Suite("Name guessing from a slug")
struct NameGuessTests {
    // Only LinkedIn slugs carry a name; the other two hand over a handle, and
    // capitalizing one produces something that looks like a name and is not.
    @Test("a LinkedIn slug becomes a name worth confirming")
    func linkedInSlug() {
        #expect(ProfileURL.nameGuess(fromSlug: "mai-tran-8a91b2") == "Mai Tran")
    }

    // JS \d is ASCII only. CharacterSet.decimalDigits is every Unicode digit,
    // so a slug carrying an Arabic-Indic numeral would lose a segment here and
    // keep it on the server.
    @Test("only ASCII digits mark a segment as id junk")
    func asciiDigitsOnly() {
        #expect(ProfileURL.nameGuess(fromSlug: "mai-tran-\u{0661}\u{0662}") == "Mai Tran \u{0661}\u{0662}")
    }
}
