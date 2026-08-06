import Foundation
import Testing
@testable import Haven

/// `InstagramWebProfileInfo.platformId`: the one piece of `PlatformIdResolving`
/// that is pure and worth pinning without a network call. The fetch itself
/// (`LivePlatformIdResolving.instagramId`) is exercised on a real device, the
/// same way `ConvexCaptureSink`'s other network calls are -- this is the parse
/// the fetch hands its response to.
@Suite("Parsing Instagram's own profile-info response")
struct InstagramWebProfileInfoTests {
    @Test("a clean response yields the numeric id")
    func good() throws {
        let json = """
            {"data": {"user": {"id": "1477479148", "username": "mai.makes"}}, "status": "ok"}
            """
        let parsed = try JSONDecoder().decode(InstagramWebProfileInfo.self, from: Data(json.utf8))
        #expect(parsed.platformId == "1477479148")
    }

    @Test("a response with no user at all has no id")
    func missingUser() throws {
        let json = #"{"data": {"user": null}, "status": "ok"}"#
        let parsed = try JSONDecoder().decode(InstagramWebProfileInfo.self, from: Data(json.utf8))
        #expect(parsed.platformId == nil)
    }

    @Test("a response with no data key at all has no id")
    func missingData() throws {
        let json = #"{"status": "fail", "message": "user not found"}"#
        let parsed = try JSONDecoder().decode(InstagramWebProfileInfo.self, from: Data(json.utf8))
        #expect(parsed.platformId == nil)
    }

    @Test("a user with no id field has no id")
    func missingId() throws {
        let json = #"{"data": {"user": {"username": "mai.makes"}}}"#
        let parsed = try JSONDecoder().decode(InstagramWebProfileInfo.self, from: Data(json.utf8))
        #expect(parsed.platformId == nil)
    }

    // The endpoint is undocumented and carries no contract that the id always
    // arrives quoted -- reading it as either shape is what "parse defensively"
    // means in practice.
    @Test("an id sent as a JSON number is read the same as a string")
    func numericId() throws {
        let json = #"{"data": {"user": {"id": 1477479148}}}"#
        let parsed = try JSONDecoder().decode(InstagramWebProfileInfo.self, from: Data(json.utf8))
        #expect(parsed.platformId == "1477479148")
    }

    @Test("a blank id string is treated as no id")
    func blankId() throws {
        let json = #"{"data": {"user": {"id": "   "}}}"#
        let parsed = try JSONDecoder().decode(InstagramWebProfileInfo.self, from: Data(json.utf8))
        #expect(parsed.platformId == nil)
    }

    @Test("garbage that is not this shape at all fails to decode rather than crash")
    func garbage() {
        let json = #"["not", "an", "object"]"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(InstagramWebProfileInfo.self, from: Data(json.utf8))
        }
    }

    @Test("empty bytes fail to decode rather than crash")
    func empty() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(InstagramWebProfileInfo.self, from: Data())
        }
    }
}

/// `ResolveXUsernameResponse.resolvedPlatformId`: the pure decision behind
/// `LivePlatformIdResolving.xId` -- resolved-before-save so
/// `saveSharedProfile`'s id-first lookup can attach a rename to the person
/// who already holds the account (see I2). Only "resolved" ever carries a
/// usable id; "unavailable" and "failed" both mean "nothing to send".
@Suite("Deciding whether resolveXUsername resolved anything")
struct ResolveXUsernameResponseTests {
    @Test("resolved with a clean id is usable")
    func resolved() {
        let response = ResolveXUsernameResponse(status: "resolved", platformId: "1477479148")
        #expect(response.resolvedPlatformId == "1477479148")
    }

    @Test("unavailable never carries an id through, even if one is present")
    func unavailable() {
        let response = ResolveXUsernameResponse(status: "unavailable", platformId: "1477479148")
        #expect(response.resolvedPlatformId == nil)
    }

    @Test("failed never carries an id through")
    func failed() {
        let response = ResolveXUsernameResponse(status: "failed", platformId: nil)
        #expect(response.resolvedPlatformId == nil)
    }

    @Test("resolved with a blank id is treated as no id")
    func resolvedButBlank() {
        let response = ResolveXUsernameResponse(status: "resolved", platformId: "   ")
        #expect(response.resolvedPlatformId == nil)
    }

    @Test("the response decodes from the documented resolved shape")
    func decodesResolved() throws {
        let json = #"{"status": "resolved", "platformId": "1477479148"}"#
        let response = try JSONDecoder().decode(ResolveXUsernameResponse.self, from: Data(json.utf8))
        #expect(response.resolvedPlatformId == "1477479148")
    }

    @Test("the response decodes from the documented unavailable shape, with no platformId key at all")
    func decodesUnavailable() throws {
        let json = #"{"status": "unavailable"}"#
        let response = try JSONDecoder().decode(ResolveXUsernameResponse.self, from: Data(json.utf8))
        #expect(response.resolvedPlatformId == nil)
    }
}
