import ConvexMobile
import Foundation

/// What `composio:initiateSocialConnection` answers.
enum InitiateResult: Equatable {
    /// Nothing to prove yet: open `url` in a browser, then poll
    /// `connectedAccountId` with `ContactConnector.poll`.
    case redirect(url: URL, connectedAccountId: String)
    /// Already connected -- Composio's own dedupe found a live connection, so
    /// there is no browser trip at all.
    case already(handle: String)
    /// The account exists but is a kind Composio's profile tool cannot read
    /// (a personal Instagram account, not creator or business).
    case unsupportedAccount
    case failed
}

/// What `ContactConnector.poll` settles on, once a browser trip is done.
enum SocialConnectOutcome: Equatable {
    /// `photoUrl` is Composio's, not Haven's: nil wherever the platform's
    /// profile tool did not hand one back, which for LinkedIn and Instagram
    /// never happens and for X is the common case (see `PROFILE_TOOL`'s
    /// comment on `composio.ts` -- X's photo field is not live-proven).
    case connected(handle: String, photoUrl: String?)
    case unsupportedAccount
    /// The connection failed or expired, or nothing came back before the
    /// deadline -- polling never distinguishes the two, because neither is
    /// something the person can act on differently.
    case failed
    /// Backing out of the browser page. A choice, not a failure.
    case cancelled
}

/// Links a social platform to the signed-in person through Composio, not
/// Clerk.
///
/// Composio's managed OAuth apps return what these platforms hide from
/// Clerk's own connections: LinkedIn's real vanityName, and a username for an
/// Instagram creator or business account -- both, where the same call proves
/// one, with a profile photo URL. Clerk still signs people in; this type
/// never touches identity, only what a connection proves. The backend does
/// the platform-specific work (`convex/composio.ts`) and never downloads the
/// photo itself -- this is transport and polling only, and `OnboardingModel`
/// is what imports the URL it hands back.
enum ContactConnector {
    /// How often a browser trip is checked while it is open.
    private static let pollInterval: Duration = .seconds(2)
    /// How long altogether: long enough to actually authorize in the browser,
    /// short enough that walking away does not poll forever.
    private static let pollDeadline: TimeInterval = 120

    /// Starts a connection for `platform`. Never called for `.phone`, which
    /// has nothing to authorize against -- `ContactScreen` keeps it in the
    /// typed group, so this is a defensive `.failed` rather than a crash.
    static func initiate(_ platform: MyCard.Platform) async -> InitiateResult {
        guard platform != .phone else { return .failed }
        let work = Task { () throws -> InitiateResponse in
            try await convex.action(
                "composio:initiateSocialConnection",
                with: ["platform": platform.rawValue]
            )
        }
        guard let response = await work.value(within: .seconds(HavenNetwork.deadline)) else {
            return .failed
        }
        return Self.map(response)
    }

    /// Polls after the browser trip, until Composio says what happened or the
    /// deadline is reached.
    ///
    /// The deadline is this loop's own, not `Task.value(within:)`'s: that
    /// helper bounds the *wait*, not the *work* (see `TaskDeadline.swift`) --
    /// a task it gives up on keeps running. Wrapping this whole loop in one
    /// would leave it polling in the background forever once the bound hit,
    /// which defeats the point. Each individual poll call is bounded the same
    /// way every network call in the app is; the loop's own deadline is the
    /// thing that actually stops it.
    ///
    /// Cancelling the calling task -- the browser sheet being dismissed by
    /// hand -- ends this immediately: `Task.sleep` throws the moment
    /// cancellation lands, and that is caught below rather than left to
    /// unwind on its own, so the caller gets `.cancelled` instead of nothing.
    static func poll(platform: MyCard.Platform, connectedAccountId: String) async -> SocialConnectOutcome {
        let deadline = ContinuousClock.now.advanced(by: .seconds(pollDeadline))
        while ContinuousClock.now < deadline {
            let work = Task { () throws -> CompleteResponse in
                try await convex.action(
                    "composio:completeSocialConnection",
                    with: ["platform": platform.rawValue, "connectedAccountId": connectedAccountId]
                )
            }
            if let response = await work.value(within: .seconds(HavenNetwork.deadline)),
               let outcome = Self.step(response) {
                return outcome
            }
            // Either the call timed out, or the account is still pending --
            // both mean "ask again shortly," not "give up."
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return .cancelled
            }
        }
        return .failed
    }

    /// Pure so it is testable without a fake network: what an
    /// `initiateSocialConnection` response means to the UI.
    static func map(_ response: InitiateResponse) -> InitiateResult {
        switch response.status {
        case "redirect":
            guard let raw = response.redirectUrl, let url = URL(string: raw),
                  let connectedAccountId = response.connectedAccountId else { return .failed }
            return .redirect(url: url, connectedAccountId: connectedAccountId)
        case "already":
            guard let handle = response.handle, !handle.isEmpty else { return .failed }
            return .already(handle: handle)
        case "unsupported_account":
            return .unsupportedAccount
        default:
            return .failed
        }
    }

    /// Pure so it is testable without a fake network: what one
    /// `completeSocialConnection` response means. `nil` means "still
    /// pending, ask again" -- the only outcome `poll`'s loop does not return
    /// straight to its own caller.
    static func step(_ response: CompleteResponse) -> SocialConnectOutcome? {
        switch response.status {
        case "connected":
            guard let handle = response.handle, !handle.isEmpty else { return .failed }
            return .connected(handle: handle, photoUrl: response.photoUrl)
        case "unsupported_account":
            return .unsupportedAccount
        case "failed":
            return .failed
        default:
            return nil
        }
    }
}

struct InitiateResponse: Decodable {
    let status: String
    let redirectUrl: String?
    let connectedAccountId: String?
    let handle: String?
}

struct CompleteResponse: Decodable {
    let status: String
    let handle: String?
    let photoUrl: String?
}
