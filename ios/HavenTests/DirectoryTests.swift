import ConvexMobile
import Foundation
import Testing
@testable import Haven

// The directory shell's pure logic: what one person's line under their name
// says, and whether this phone has been told to stop suggesting the widget.
// What the screen looks like is judged in the previews and on a device.

private func decode(_ json: String) throws -> DirectoryPage {
    try JSONDecoder().decode(DirectoryPage.self, from: Data(json.utf8))
}

@Suite("Directory")
struct DirectoryTests {
    // The exact shape people:listPeople returns, including the keys the shell
    // has no use for. An unknown key must stay harmless: the server is free to
    // add fields, and Phase 2 will.
    @Test("a page decodes what people:listPeople returns")
    func decodesPage() throws {
        let page = try decode(
            """
            {
              "page": [
                {
                  "_id": "j5701abc",
                  "_creationTime": 1730000000000.5,
                  "name": "Maya Chen",
                  "company": "Haven",
                  "role": "Founder",
                  "city": { "name": "Ho Chi Minh City", "country": "Vietnam" },
                  "photoUrl": null,
                  "updatedAt": 1730000000001.5
                }
              ],
              "isDone": false,
              "continueCursor": "cursor_1"
            }
            """
        )

        #expect(page.page.count == 1)
        #expect(page.page[0].name == "Maya Chen")
        #expect(page.page[0].id == "j5701abc")
        #expect(page.isDone == false)
    }

    // What someone does places them faster than where they are, so work wins
    // when both exist. A person with neither is a name on its own, which is
    // honest rather than a gap to fill with a placeholder.
    @Test("the line under a name is whichever of work or city there is")
    func detailLine() {
        let full = DirectoryPerson(
            _id: "1",
            name: "Maya Chen",
            company: "Haven",
            role: "Founder",
            city: DirectoryPerson.City(name: "Ho Chi Minh City")
        )
        #expect(full.detail == "Founder, Haven")

        let companyOnly = DirectoryPerson(_id: "2", name: "Ada", company: "Haven")
        #expect(companyOnly.detail == "Haven")

        let roleOnly = DirectoryPerson(_id: "3", name: "Ada", role: "Founder")
        #expect(roleOnly.detail == "Founder")

        let cityOnly = DirectoryPerson(
            _id: "4",
            name: "Ada",
            city: DirectoryPerson.City(name: "London")
        )
        #expect(cityOnly.detail == "London")

        #expect(DirectoryPerson(_id: "5", name: "Ada").detail == nil)
        // A field the server stored as empty is not a line either.
        #expect(DirectoryPerson(_id: "6", name: "Ada", company: "").detail == nil)
    }

    // Dismissing the widget suggestion has to survive the app being killed, or
    // it is not a dismissal, it is a flicker.
    @Test("dismissing the widget card sticks")
    func dismissalRoundTrip() {
        let userId = "user_widget_round_trip"
        // UserDefaults outlives the run on the simulator, so this asserts about
        // this run rather than the last one.
        WidgetPromoDismissal.reset(userId: userId)
        #expect(WidgetPromoDismissal.isDismissed(userId: userId) == false)

        WidgetPromoDismissal.dismiss(userId: userId)

        #expect(WidgetPromoDismissal.isDismissed(userId: userId))
    }

    // Two accounts on one phone: inheriting the last person's dismissal would
    // hide the only working suggestion from someone who never saw it.
    @Test("a dismissal does not carry across accounts")
    func dismissalIsKeyedByUser() {
        let mine = "user_widget_mine"
        let theirs = "user_widget_theirs"
        WidgetPromoDismissal.reset(userId: mine)
        WidgetPromoDismissal.reset(userId: theirs)

        WidgetPromoDismissal.dismiss(userId: mine)

        #expect(WidgetPromoDismissal.isDismissed(userId: theirs) == false)
        #expect(WidgetPromoDismissal.isDismissed(userId: mine))
    }
}

@Suite("The People screen's title")
struct PeopleTitleTests {
    @Test("a first name gets a simple apostrophe-s")
    func possessive() {
        #expect(PeopleTitle.title(firstName: "Tony") == "Tony's Haven")
    }

    // The brief is a simple possessive, not a grammatically clever one: a name
    // already ending in "s" still gets "'s", not a bare apostrophe.
    @Test("a name ending in s still gets 's, not a bare apostrophe")
    func noSmartTrailingS() {
        #expect(PeopleTitle.title(firstName: "Chris") == "Chris's Haven")
    }

    @Test("no name loaded yet reads Your Haven, never a bare apostrophe")
    func fallsBackWithoutAName() {
        #expect(PeopleTitle.title(firstName: nil) == "Your Haven")
    }

    // A name that came back empty or all whitespace is not a name to build a
    // possessive out of -- "'s Haven" with nothing in front of it would read
    // as broken rather than as a fallback.
    @Test("an empty or blank name falls back the same way nil does")
    func emptyNameFallsBack() {
        #expect(PeopleTitle.title(firstName: "") == "Your Haven")
        #expect(PeopleTitle.title(firstName: "   ") == "Your Haven")
    }

    @Test("only the first word of a full name is used")
    func firstWordOfAFullName() {
        #expect(PeopleTitle.title(firstName: PeopleTitle.firstName(of: "Tony Nguyen")) == "Tony's Haven")
    }

    @Test("a single-word name is its own first name")
    func singleWordName() {
        #expect(PeopleTitle.firstName(of: "Ada") == "Ada")
    }

    @Test("surrounding whitespace on a full name does not leak into the title")
    func trimsBeforeSplitting() {
        #expect(PeopleTitle.firstName(of: "  Maya Chen  ") == "Maya")
    }

    @Test("no name to read from has no first name")
    func noNameNoFirstName() {
        #expect(PeopleTitle.firstName(of: nil) == nil)
    }
}

@MainActor
@Suite("Paging the directory")
struct DirectoryPagingTests {
    private func page(_ names: [String], isDone: Bool) -> DirectoryPage {
        DirectoryPage(
            page: names.enumerated().map { DirectoryPerson(_id: "p\($0.offset)", name: $0.element) },
            isDone: isDone
        )
    }

    // The window is what grows. A last page that asked for more would re-read
    // the whole directory on every scroll to the bottom, forever.
    @Test("the end of the list asks for nothing more")
    func doneMeansDone() {
        let model = DirectoryModel(preview: .ready(page(["Ada"], isDone: true)))
        let before = model.window
        model.loadMore()
        #expect(model.window == before)
        #expect(!model.isLoadingMore)
    }

    @Test("nothing is asked for before the first page has answered")
    func nothingBeforeTheFirstPage() {
        for state in [DirectoryLoad.loading, .unreachable] {
            let model = DirectoryModel(preview: state)
            let before = model.window
            model.loadMore()
            #expect(model.window == before, "\(state)")
        }
    }

    // A list scrolled hard enough to pass its own end twice while one read is
    // out must not open a second one, or the window jumps two pages for one
    // scroll and the rows arrive out of step.
    @Test("scrolling past the end twice asks once")
    func asksOnceWhileAReadIsOut() {
        let model = DirectoryModel(preview: .ready(page(["Ada"], isDone: false)))
        let before = model.window

        model.loadMore()
        let afterOne = model.window
        model.loadMore()

        #expect(afterOne > before)
        #expect(model.window == afterOne)
        #expect(model.isLoadingMore)
    }

    // ConvexEncodable wraps a FixedWidthInteger as {"$integer": base64}, and
    // paginationOptsValidator on the server is v.number() -- a float64 that
    // rejects that wrapper outright. Both listPeople reads have to travel
    // their numItems as a plain JSON number or the backend refuses the whole
    // paginationOpts object before the query ever runs.
    @Test("numItems in paginationOpts is a plain number, not a Convex Int64")
    func paginationNumbersAreNotInt64() throws {
        let directoryOpts: [String: ConvexEncodable?] = [
            "numItems": DirectoryModel(preview: .loading).window,
            "cursor": nil,
        ]
        let mirrorOpts: [String: ConvexEncodable?] = [
            "numItems": CaptureSync.mirrorSize,
            "cursor": nil,
        ]

        let directoryEncoded = try directoryOpts.convexEncode()
        let mirrorEncoded = try mirrorOpts.convexEncode()

        #expect(!directoryEncoded.contains("$integer"), "\(directoryEncoded)")
        #expect(!mirrorEncoded.contains("$integer"), "\(mirrorEncoded)")
    }
}

@MainActor
@Suite("The directory's two suggestions")
struct DirectoryPromoTests {
    // Distinct from people.isEmpty, which is also true while the read is in
    // flight. A suggestion that flashed up during loading and vanished when the
    // first page landed would be worse than one that waits a beat.
    @Test("a directory is empty only once it has answered")
    func emptyMeansAnswered() {
        #expect(!DirectoryModel(preview: .loading).isEmpty)
        #expect(!DirectoryModel(preview: .unreachable).isEmpty)
        #expect(DirectoryModel(preview: .ready(DirectoryPage(page: [], isDone: true))).isEmpty)
        #expect(
            !DirectoryModel(
                preview: .ready(
                    DirectoryPage(page: [DirectoryPerson(_id: "p1", name: "Ada")], isDone: true)
                )
            ).isEmpty
        )
    }

    // Turning down the widget says nothing about wanting Haven in the share
    // sheet. One key hiding both would take away the one that matters most.
    @Test("the two suggestions are dismissed separately")
    func dismissalsAreSeparate() {
        let userId = "user_two_promos"
        WidgetPromoDismissal.reset(userId: userId)
        SharePromoDismissal.reset(userId: userId)

        WidgetPromoDismissal.dismiss(userId: userId)

        #expect(WidgetPromoDismissal.isDismissed(userId: userId))
        #expect(!SharePromoDismissal.isDismissed(userId: userId))
    }

    @Test("dismissing the share sheet card sticks, and only for this account")
    func sharePromoDismissalIsKeyedByUser() {
        let mine = "user_share_promo_mine"
        let theirs = "user_share_promo_theirs"
        SharePromoDismissal.reset(userId: mine)
        SharePromoDismissal.reset(userId: theirs)

        SharePromoDismissal.dismiss(userId: mine)

        #expect(SharePromoDismissal.isDismissed(userId: mine))
        #expect(!SharePromoDismissal.isDismissed(userId: theirs))
    }
}
