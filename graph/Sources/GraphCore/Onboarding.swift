import Foundation

/// Where the user is in the MVP onboarding flow: first launch -> Welcome -> Authorize ->
/// "Map relationships" -> extraction/build progress -> their sky, in-app. A pure state
/// machine on purpose -- AppModel owns the UserDefaults flag and the live permission
/// probes; this type never touches either, which is what keeps it testable without a
/// simulator or a real chat.db.
public enum OnboardingStep: Equatable, Sendable {
    case welcome
    case authorize
    case readyToMap
    case mapping
    case sky
}

/// What can move the flow from one step to the next. Deliberately narrower than "any
/// AppModel method call" -- only the four things a view can actually trigger.
public enum OnboardingEvent: Equatable, Sendable {
    case continueFromWelcome
    case permissionsConfirmed
    case startMapping
    case mapCompleted
    /// A relaunch, or a mid-session permission change AppModel detects on Re-check,
    /// found Messages access gone. Always routes back to `.authorize`, from any step --
    /// mapping against a database that can no longer be opened is not a state to enter.
    case permissionsRevoked
}

/// Three-state, not a bool: an empty address book is not "blocked", it is "nothing to
/// enrich with" (AppModel.discoverContactsDatabasePaths already treats a missing
/// AddressBook directory as normal, not an error). Collapsing that into a bool would
/// make Authorize's Continue gate unpassable on a Mac with no Contacts data at all.
public enum ContactsAccessState: Equatable, Sendable {
    case granted
    case blocked
    case noData
}

public enum Onboarding {
    /// Where a launch lands, before any onboarding event has fired this session. Messages
    /// access wins over everything else: a relaunch that finds Full Disk Access revoked
    /// must fall back to `.authorize`, never `.mapping` or `.sky`, even if onboarding was
    /// marked completed and a previously-built sky is still sitting on disk -- that sky
    /// is only reachable again once access is proven live again, not assumed from history.
    public static func initialStep(
        hasCompletedOnboarding: Bool,
        messagesGranted: Bool,
        hasBuiltSky: Bool
    ) -> OnboardingStep {
        // A fresh install has never granted anything yet -- that is what Welcome and
        // Authorize are FOR, so an ungranted probe here means "show them", not "skip
        // straight past onboarding". Only once onboarding has completed once does a
        // missing grant mean something was taken away, which routes to Authorize instead.
        guard hasCompletedOnboarding else { return .welcome }
        guard messagesGranted else { return .authorize }
        return hasBuiltSky ? .sky : .readyToMap
    }

    /// The transition table. Unhandled (step, event) pairs return `step` unchanged rather
    /// than trapping: a stray double-tap (e.g. Continue fired twice before the view
    /// re-renders) should be a no-op, not a crash.
    public static func next(from step: OnboardingStep, event: OnboardingEvent) -> OnboardingStep {
        if event == .permissionsRevoked {
            return .authorize
        }
        switch (step, event) {
        case (.welcome, .continueFromWelcome):
            return .authorize
        case (.authorize, .permissionsConfirmed):
            return .readyToMap
        case (.readyToMap, .startMapping):
            return .mapping
        case (.mapping, .mapCompleted):
            return .sky
        default:
            return step
        }
    }

    /// Authorize's Continue gate: Messages access is required (there is no graph without
    /// it), Contacts is an enrichment so `.noData` passes the gate the same as `.granted`
    /// -- only a Contacts store that exists but would not open (`.blocked`) holds Continue
    /// back, since that is the one state actually worth telling the user to go fix.
    public static func canProceedFromAuthorize(
        messagesGranted: Bool,
        contactsState: ContactsAccessState
    ) -> Bool {
        messagesGranted && contactsState != .blocked
    }
}
