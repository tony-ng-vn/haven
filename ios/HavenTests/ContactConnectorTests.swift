import Foundation
import Testing

@testable import Haven

/// `ContactConnector.map` and `.step` are the two places a Composio status
/// string becomes something the UI acts on -- everything downstream reads
/// the enum, never the string, so this is where a status Composio starts
/// sending that this code does not recognise would first show up.
@Suite("Composio outcome mapping")
struct ContactConnectorOutcomeTests {
    @Test("a redirect carries a usable URL and the id to poll")
    func redirect() {
        let response = InitiateResponse(
            status: "redirect",
            redirectUrl: "https://backend.composio.dev/redirect",
            connectedAccountId: "ca_test",
            handle: nil
        )
        #expect(
            ContactConnector.map(response)
                == .redirect(
                    url: URL(string: "https://backend.composio.dev/redirect")!,
                    connectedAccountId: "ca_test"
                )
        )
    }

    @Test("a redirect with no usable URL fails rather than opening a broken browser")
    func redirectWithoutURL() {
        let response = InitiateResponse(
            status: "redirect", redirectUrl: nil, connectedAccountId: "ca_test", handle: nil
        )
        #expect(ContactConnector.map(response) == .failed)
    }

    @Test("already connected carries the proven handle, with no browser trip")
    func already() {
        let response = InitiateResponse(
            status: "already", redirectUrl: nil, connectedAccountId: nil, handle: "tony-buildd"
        )
        #expect(ContactConnector.map(response) == .already(handle: "tony-buildd"))
    }

    @Test("an unsupported account is its own case, not a generic failure")
    func unsupportedAccount() {
        let response = InitiateResponse(
            status: "unsupported_account", redirectUrl: nil, connectedAccountId: nil, handle: nil
        )
        #expect(ContactConnector.map(response) == .unsupportedAccount)
    }

    @Test("an unrecognised status fails rather than being guessed at")
    func unknownInitiateStatus() {
        let response = InitiateResponse(
            status: "something_new", redirectUrl: nil, connectedAccountId: nil, handle: nil
        )
        #expect(ContactConnector.map(response) == .failed)
    }

    @Test("still pending means keep polling, not any terminal outcome")
    func pending() {
        #expect(ContactConnector.step(CompleteResponse(status: "pending", handle: nil, photoUrl: nil)) == nil)
    }

    @Test("connected carries the proven handle, with no photo when Composio sent none")
    func connected() {
        let outcome = ContactConnector.step(
            CompleteResponse(status: "connected", handle: "tony-buildd", photoUrl: nil)
        )
        #expect(outcome == .connected(handle: "tony-buildd", photoUrl: nil))
    }

    @Test("connected carries the photo URL too, when Composio's tool proved one")
    func connectedWithPhoto() {
        let outcome = ContactConnector.step(
            CompleteResponse(
                status: "connected",
                handle: "tony-buildd",
                photoUrl: "https://media.licdn.com/dms/image/tony.jpg"
            )
        )
        #expect(
            outcome
                == .connected(handle: "tony-buildd", photoUrl: "https://media.licdn.com/dms/image/tony.jpg")
        )
    }

    @Test("connected with no handle fails rather than storing an empty one")
    func connectedWithoutHandle() {
        #expect(
            ContactConnector.step(CompleteResponse(status: "connected", handle: nil, photoUrl: nil)) == .failed
        )
    }

    @Test("an unsupported account stays its own case through polling too")
    func pollUnsupportedAccount() {
        #expect(
            ContactConnector.step(CompleteResponse(status: "unsupported_account", handle: nil, photoUrl: nil))
                == .unsupportedAccount
        )
    }

    @Test("failed is failed")
    func failed() {
        #expect(ContactConnector.step(CompleteResponse(status: "failed", handle: nil, photoUrl: nil)) == .failed)
    }

    @Test("an unrecognised status keeps polling rather than giving up early")
    func unknownCompleteStatus() {
        #expect(
            ContactConnector.step(CompleteResponse(status: "something_new", handle: nil, photoUrl: nil)) == nil
        )
    }
}

/// Haven's own platform names are Composio's action argument directly --
/// `composio.ts`'s `platformValidator` takes `"linkedin" | "instagram" |
/// "x"` verbatim, so there is exactly one place the two vocabularies meet,
/// and this is what would catch either side drifting from it.
@Suite("Platform argument")
struct ContactConnectorPlatformArgumentTests {
    @Test("every connectable platform's raw value is what Composio expects")
    func rawValues() {
        #expect(MyCard.Platform.linkedin.rawValue == "linkedin")
        #expect(MyCard.Platform.instagram.rawValue == "instagram")
        #expect(MyCard.Platform.x.rawValue == "x")
    }

    @Test("phone never reaches Composio -- initiate fails it without a network call")
    func phoneIsRefused() async {
        #expect(await ContactConnector.initiate(.phone) == .failed)
    }
}
