import Foundation
import EventKit
import Testing
@testable import Haven

@Suite("Apple Calendar event picker")
struct AppleCalendarTests {
    @Test("nearby events are ordered for the moment someone is starting Event Mode")
    func nearbyRanking() {
        let now = Date(timeIntervalSince1970: 10_000)
        let events = [
            candidate("recent", "Recently ended", start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(-600)),
            candidate("all-day", "Conference day", start: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(7_200), isAllDay: true),
            candidate("later", "Later today", start: now.addingTimeInterval(7_200), end: now.addingTimeInterval(9_000)),
            candidate("next", "Next meeting", start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(3_600)),
            candidate("ongoing-old", "Long session", start: now.addingTimeInterval(-1_800), end: now.addingTimeInterval(1_800)),
            candidate("ongoing-new", "Just started", start: now.addingTimeInterval(-300), end: now.addingTimeInterval(3_000))
        ]

        let ranked = CalendarEventCandidate.ranked(events, around: now)

        #expect(ranked.map(\.id) == [
            "ongoing-new", "ongoing-old", "next", "later", "all-day", "recent"
        ])
    }

    @Test("opening the sheet never asks for calendar access")
    @MainActor
    func loadDoesNotPrompt() async {
        let provider = CalendarProviderStub(access: .notDetermined)
        let model = AppleCalendarModel(provider: provider)

        await model.loadIfAuthorized(around: Date(timeIntervalSince1970: 20_000))

        #expect(model.state == .needsPermission)
        #expect(await provider.requestCount == 0)
        #expect(await provider.loadCount == 0)
    }

    @Test("tapping the calendar option requests access and loads nearby events")
    @MainActor
    func requestThenLoad() async {
        let now = Date(timeIntervalSince1970: 30_000)
        let event = candidate("event", "Founders dinner", start: now, end: now.addingTimeInterval(3_600))
        let provider = CalendarProviderStub(access: .notDetermined, requestResult: .fullAccess, events: [event])
        let model = AppleCalendarModel(provider: provider)

        await model.requestAccessAndLoad(around: now)

        #expect(model.state == .ready([event]))
        #expect(await provider.requestCount == 1)
        #expect(await provider.loadCount == 1)
    }

    @Test("denied access leaves manual event entry available")
    @MainActor
    func deniedAccess() async {
        let provider = CalendarProviderStub(access: .denied)
        let model = AppleCalendarModel(provider: provider)

        await model.loadIfAuthorized()

        #expect(model.state == .denied)
        #expect(await provider.requestCount == 0)
        #expect(await provider.loadCount == 0)
    }

    @Test("an empty calendar is represented as a usable empty state")
    @MainActor
    func emptyCalendar() async {
        let provider = CalendarProviderStub(access: .fullAccess, events: [])
        let model = AppleCalendarModel(provider: provider)

        await model.loadIfAuthorized()

        #expect(model.state == .ready([]))
        #expect(await provider.loadCount == 1)
    }

    @Test("a permission request error is not presented as a denial")
    @MainActor
    func permissionError() async {
        let provider = CalendarProviderStub(access: .notDetermined, requestError: true)
        let model = AppleCalendarModel(provider: provider)

        await model.requestAccessAndLoad()

        #expect(model.state == .failed)
        #expect(await provider.requestCount == 1)
    }

    @Test("revoking access clears previously loaded candidates")
    @MainActor
    func revokedAccess() async {
        let now = Date(timeIntervalSince1970: 40_000)
        let event = candidate("event", "Private dinner", start: now, end: now.addingTimeInterval(3_600))
        let provider = CalendarProviderStub(access: .fullAccess, events: [event])
        let model = AppleCalendarModel(provider: provider)
        await model.loadIfAuthorized(around: now)
        #expect(model.state == .ready([event]))

        await provider.setAccess(.denied)
        await model.loadIfAuthorized(around: now)

        #expect(model.state == .denied)
    }

    @Test("canceled calendar events are excluded")
    func canceledEvents() {
        #expect(AppleCalendarProvider.includes(status: .confirmed))
        #expect(AppleCalendarProvider.includes(status: .tentative))
        #expect(AppleCalendarProvider.includes(status: .none))
        #expect(!AppleCalendarProvider.includes(status: .canceled))
    }

    private func candidate(
        _ id: String,
        _ title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false
    ) -> CalendarEventCandidate {
        CalendarEventCandidate(
            id: id,
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay
        )
    }
}

private actor CalendarProviderStub: AppleCalendarProviding {
    var access: AppleCalendarAccess
    var requestResult: AppleCalendarAccess
    var events: [CalendarEventCandidate]
    let requestError: Bool
    var requestCount = 0
    var loadCount = 0

    init(
        access: AppleCalendarAccess,
        requestResult: AppleCalendarAccess? = nil,
        events: [CalendarEventCandidate] = [],
        requestError: Bool = false
    ) {
        self.access = access
        self.requestResult = requestResult ?? access
        self.events = events
        self.requestError = requestError
    }

    func accessStatus() -> AppleCalendarAccess {
        access
    }

    func requestFullAccess() async throws -> AppleCalendarAccess {
        requestCount += 1
        if requestError { throw CalendarProviderStubError.requestFailed }
        access = requestResult
        return requestResult
    }

    func nearbyEvents(around date: Date) async throws -> [CalendarEventCandidate] {
        loadCount += 1
        return events
    }

    func setAccess(_ access: AppleCalendarAccess) {
        self.access = access
    }
}

private enum CalendarProviderStubError: Error {
    case requestFailed
}
