import Foundation
import Testing
@testable import Haven

private func person(
    id: String,
    name: String,
    handles: [MirrorHandle] = []
) -> MirrorPerson {
    MirrorPerson(id: id, name: name, handles: handles)
}

private let mai = person(
    id: "p1",
    name: "Nguy\u{1ec5}n Mai",
    handles: [MirrorHandle(platform: "instagram", value: "mai.makes")]
)
private let duc = person(
    id: "p2",
    name: "\u{110}\u{1ee9}c Anh",
    handles: [MirrorHandle(platform: "linkedin", value: "duc-anh-8a91b2")]
)
private let mai2 = person(id: "p3", name: "Mai Tran")

private let mirror = DirectoryMirror(
    refreshedAt: Date(timeIntervalSince1970: 1_000),
    people: [mai, duc, mai2]
)

@Suite("Reading the directory mirror")
struct DirectoryMirrorLookupTests {
    // The sheet's "you already know them", answered offline. Handle identity
    // is the one thing the mirror can be sure of: the server keys on exactly
    // this pair.
    @Test("a handle already in the directory finds its person")
    func findByHandle() {
        #expect(
            mirror.person(holding: ProfileLink(platform: .instagram, handle: "mai.makes"))
                == mai
        )
    }

    // The same account arrives as "@Mai.Makes" from one surface and
    // "mai.makes" from another, and the server folds both to one key.
    @Test("case, spaces and a leading @ never split one account in two")
    func handleFolding() {
        for shape in ["@mai.makes", "MAI.MAKES", "  @Mai.Makes  ", "@@mai.makes"] {
            #expect(
                mirror.person(holding: ProfileLink(platform: .instagram, handle: shape))
                    == mai,
                "\(shape)"
            )
        }
    }

    // One person, many platforms. The same handle text on a platform they are
    // not on is somebody else.
    @Test("a handle on another platform is another account")
    func platformSeparates() {
        #expect(
            mirror.person(holding: ProfileLink(platform: .x, handle: "mai.makes")) == nil
        )
    }

    @Test("a handle nobody holds finds nobody")
    func unknownHandle() {
        #expect(
            mirror.person(holding: ProfileLink(platform: .instagram, handle: "stranger"))
                == nil
        )
    }

    // The "add to <recent person>" offer. A LinkedIn slug guesses a name, and
    // a name typed with accents has to reach the person stored with them.
    @Test("a guessed name reaches the person however it is accented")
    func matchByName() {
        #expect(mirror.people(named: "nguyen mai") == [mai])
        #expect(mirror.people(named: "Nguy\u{1ec5}n MAI") == [mai])
        #expect(mirror.people(named: "duc anh") == [duc])
    }

    // Two people can share a name, and the sheet has to offer both rather
    // than pick one. Haven never guesses two people are one.
    @Test("a shared name offers everybody who holds it")
    func matchByNameAmbiguous() {
        let twins = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 0),
            people: [mai, person(id: "p9", name: "nguyen mai")]
        )
        #expect(twins.people(named: "Nguy\u{1ec5}n Mai").map(\.id) == ["p1", "p9"])
    }

    @Test("an empty name matches nobody rather than everybody")
    func emptyName() {
        #expect(mirror.people(named: "").isEmpty)
        #expect(mirror.people(named: "   ").isEmpty)
    }

    // The small search field in the sheet. Partial, because someone typing
    // "mai" has not finished typing.
    @Test("search matches part of a name")
    func search() {
        #expect(mirror.search("mai").map(\.id) == ["p1", "p3"])
        #expect(mirror.search("tran").map(\.id) == ["p3"])
        #expect(mirror.search("anh").map(\.id) == ["p2"])
    }

    @Test("search ignores accents and case, like the server's does")
    func searchFolding() {
        #expect(mirror.search("NGUYEN").map(\.id) == ["p1"])
        #expect(mirror.search("\u{111}\u{1ee9}c").map(\.id) == ["p2"])
    }

    // An empty query is not "everyone" -- a sheet that opens on the whole
    // directory has answered a question nobody asked.
    @Test("an empty query returns nobody")
    func emptySearch() {
        #expect(mirror.search("").isEmpty)
        #expect(mirror.search("  ").isEmpty)
    }

    @Test("search stops at the limit it is given")
    func searchLimit() {
        #expect(mirror.search("mai", limit: 1).map(\.id) == ["p1"])
    }
}

@Suite("Storing the directory mirror")
struct DirectoryMirrorStoreTests {
    private func makeStore() -> (store: DirectoryMirrorStore, root: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("haven-mirror-\(UUID().uuidString)")
        return (DirectoryMirrorStore(directory: root), root)
    }

    @Test("the mirror survives the round trip whole")
    func roundTrip() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try store.save(mirror)
        #expect(store.load() == mirror)
    }

    // The mirror is a cache, never the source of truth. Before the app has
    // ever run, there is nothing to read, and the sheet still has to open.
    @Test("no mirror yet is nobody, not a failure")
    func missingMirror() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(store.load() == nil)
    }

    @Test("an unreadable mirror is nobody, not a crash")
    func corruptMirror() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
        try Data("half a wri".utf8).write(to: store.fileURL)
        #expect(store.load() == nil)
    }

    // The app rewrites the mirror after every sync while the extension may be
    // reading it. A replaced file is never a half-written one.
    @Test("a rewrite replaces the mirror rather than editing it in place")
    func rewrite() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try store.save(mirror)
        let smaller = DirectoryMirror(
            refreshedAt: Date(timeIntervalSince1970: 2_000), people: [duc]
        )
        try store.save(smaller)
        #expect(store.load() == smaller)
    }
}

@Suite("Handle keys match the server's")
struct HandleKeyCrossLanguageTests {
    @Test("every handle folds to the display value and key the server writes")
    func matchesTypeScript() {
        for (input, display, key) in handleKeyCases {
            #expect(
                MirrorHandle.displayValue(input) == display,
                "displayValue(\(input)): got \(MirrorHandle.displayValue(input)), want \(display)"
            )
            #expect(
                MirrorHandle.valueKey(input) == key,
                "valueKey(\(input)): got \(MirrorHandle.valueKey(input)), want \(key)"
            )
        }
    }
}
