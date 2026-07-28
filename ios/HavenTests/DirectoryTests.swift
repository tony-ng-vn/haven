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

@MainActor
@Suite("Paging the directory")
struct DirectoryPagingTests {
    private func page(_ names: [String], isDone: Bool) -> DirectoryPage {
        DirectoryPage(
            page: names.enumerated().map { DirectoryPerson(_id: "p\($0.offset)", name: $0.element) },
            isDone: isDone
        )
    }

    // The count was a floor that never resolved: somebody with three hundred
    // people saw "People 50+" forever, because only fifty were ever asked for.
    @Test("the count says it is a floor only while there is more to come")
    func countIsAFloorUntilItIsNot() {
        let more = DirectoryModel(preview: .ready(page(["Ada", "Mai"], isDone: false)))
        #expect(more.count == 2)
        #expect(more.countIsPartial)

        let all = DirectoryModel(preview: .ready(page(["Ada", "Mai"], isDone: true)))
        #expect(all.count == 2)
        #expect(!all.countIsPartial)
    }

    // Nobody and could-not-read are different facts, and only one of them is
    // "nobody". Unchanged by paging, and worth keeping that way.
    @Test("a directory that could not be read has no count at all")
    func noCountWithoutAnAnswer() {
        #expect(DirectoryModel(preview: .loading).count == nil)
        #expect(DirectoryModel(preview: .unreachable).count == nil)
        #expect(!DirectoryModel(preview: .unreachable).countIsPartial)
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
}
