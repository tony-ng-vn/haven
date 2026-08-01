import XCTest
@testable import GraphCore

final class OnboardingTests: XCTestCase {

    // MARK: - Fresh launch ordering

    func testFreshInstallStartsAtWelcome() {
        let step = Onboarding.initialStep(
            hasCompletedOnboarding: false,
            messagesGranted: false,
            hasBuiltSky: false
        )
        XCTAssertEqual(step, .welcome)
    }

    func testFreshLaunchWalksWelcomeThroughSkyInOrder() {
        var step = OnboardingStep.welcome
        step = Onboarding.next(from: step, event: .continueFromWelcome)
        XCTAssertEqual(step, .authorize)

        step = Onboarding.next(from: step, event: .permissionsConfirmed)
        XCTAssertEqual(step, .readyToMap)

        step = Onboarding.next(from: step, event: .startMapping)
        XCTAssertEqual(step, .mapping)

        step = Onboarding.next(from: step, event: .mapCompleted)
        XCTAssertEqual(step, .sky)
    }

    func testOutOfOrderEventsAreNoOps() {
        // A stray "mapCompleted" while still on welcome (e.g. a double-fired button)
        // must not skip the whole flow.
        XCTAssertEqual(Onboarding.next(from: .welcome, event: .mapCompleted), .welcome)
        XCTAssertEqual(Onboarding.next(from: .authorize, event: .startMapping), .authorize)
    }

    // MARK: - Both-permissions gate

    func testContinueDisabledUntilMessagesGranted() {
        XCTAssertFalse(Onboarding.canProceedFromAuthorize(messagesGranted: false, contactsState: .granted))
        XCTAssertFalse(Onboarding.canProceedFromAuthorize(messagesGranted: false, contactsState: .noData))
    }

    func testContinueDisabledWhileContactsBlocked() {
        XCTAssertFalse(Onboarding.canProceedFromAuthorize(messagesGranted: true, contactsState: .blocked))
    }

    func testContinueEnabledWhenMessagesGrantedAndContactsGrantedOrAbsent() {
        XCTAssertTrue(Onboarding.canProceedFromAuthorize(messagesGranted: true, contactsState: .granted))
        // No address book at all is not a block -- Contacts is enrichment, not required.
        XCTAssertTrue(Onboarding.canProceedFromAuthorize(messagesGranted: true, contactsState: .noData))
    }

    // MARK: - Relaunch after completion

    func testRelaunchAfterCompletionWithBuiltSkyGoesStraightToSky() {
        let step = Onboarding.initialStep(
            hasCompletedOnboarding: true,
            messagesGranted: true,
            hasBuiltSky: true
        )
        XCTAssertEqual(step, .sky)
    }

    func testRelaunchAfterCompletionWithoutBuiltSkyGoesToReadyToMap() {
        // Onboarding was finished before, but the built HTML is gone (e.g. Application
        // Support was cleared) -- re-map, do not re-run Welcome/Authorize.
        let step = Onboarding.initialStep(
            hasCompletedOnboarding: true,
            messagesGranted: true,
            hasBuiltSky: false
        )
        XCTAssertEqual(step, .readyToMap)
    }

    // MARK: - Relaunch with permissions revoked

    func testRelaunchWithMessagesAccessRevokedFallsBackToAuthorizeNotMapping() {
        // Onboarding completed and a sky was built previously, but Full Disk Access has
        // since been revoked in System Settings -- must not crash into `.mapping` or
        // silently show a stale `.sky` as if access were still live.
        let step = Onboarding.initialStep(
            hasCompletedOnboarding: true,
            messagesGranted: false,
            hasBuiltSky: true
        )
        XCTAssertEqual(step, .authorize)
    }

    func testPermissionsRevokedEventRoutesToAuthorizeFromAnyStep() {
        XCTAssertEqual(Onboarding.next(from: .mapping, event: .permissionsRevoked), .authorize)
        XCTAssertEqual(Onboarding.next(from: .sky, event: .permissionsRevoked), .authorize)
        XCTAssertEqual(Onboarding.next(from: .readyToMap, event: .permissionsRevoked), .authorize)
    }
}
