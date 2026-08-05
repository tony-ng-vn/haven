import Foundation
import Testing
@testable import Haven

// DevBuildLabel is the testable half of the dev build caption; DevBuildInfo
// (the bundle/filesystem read) is the thin shim it deliberately stays
// separate from, and is not tested here for the same reason nothing else in
// the app unit-tests Bundle.main or FileManager directly.

private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, in zone: TimeZone) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    return calendar.date(from: components)!
}

@Suite("The dev build caption")
struct DevBuildLabelTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    @Test("a version and a build time read as one line")
    func fullCaption() {
        let builtAt = date(year: 2026, month: 8, day: 4, hour: 16, minute: 41, in: pacific)
        let caption = DevBuildLabel.caption(version: "1.0.0", builtAt: builtAt, timeZone: pacific)
        #expect(caption == "v1.0.0 - built Aug 4, 4:41 PM")
    }

    // The whole point of the parameter: a test that only ever sees the host
    // machine's own zone could not tell a real timeZone read from one that
    // silently fell back to a default.
    @Test("the time zone actually changes the printed time")
    func timeZoneIsRespected() {
        let builtAt = date(year: 2026, month: 8, day: 4, hour: 16, minute: 41, in: pacific)
        let utc = TimeZone(identifier: "UTC")!
        let caption = DevBuildLabel.caption(version: "1.0.0", builtAt: builtAt, timeZone: utc)
        // 16:41 PDT (UTC-7 in August) is 23:41 UTC.
        #expect(caption == "v1.0.0 - built Aug 4, 11:41 PM")
    }

    // Half a caption is worse than none: a bare time with no "v" in front
    // reads as a bug, and a bare version restates what Settings already
    // shows.
    @Test("a missing version means no caption")
    func noVersionMeansNoCaption() {
        let builtAt = date(year: 2026, month: 8, day: 4, hour: 16, minute: 41, in: pacific)
        #expect(DevBuildLabel.caption(version: nil, builtAt: builtAt, timeZone: pacific) == nil)
    }

    @Test("an empty version means no caption")
    func emptyVersionMeansNoCaption() {
        let builtAt = date(year: 2026, month: 8, day: 4, hour: 16, minute: 41, in: pacific)
        #expect(DevBuildLabel.caption(version: "", builtAt: builtAt, timeZone: pacific) == nil)
    }

    @Test("a missing build time means no caption")
    func noBuiltAtMeansNoCaption() {
        #expect(DevBuildLabel.caption(version: "1.0.0", builtAt: nil, timeZone: pacific) == nil)
    }
}
