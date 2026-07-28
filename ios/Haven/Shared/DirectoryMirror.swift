import Foundation

/// One account on one platform, as the card stores it.
///
/// `platform` is a plain string rather than `SharedPlatform`: the card lets
/// people add handles for platforms Haven has never heard of, and a mirror
/// that dropped those would answer "you do not know them" about somebody the
/// server knows perfectly well.
struct MirrorHandle: Codable, Equatable, Sendable {
    let platform: String
    let value: String

    /// The display shape of a handle: what renders on the card. A port of
    /// `handleDisplayValue` in `convex/handleKeys.ts`.
    static func displayValue(_ value: String) -> String {
        String(value.trimmedLikeJS.drop { $0 == "@" })
    }

    /// The identity behind a handle: the same account shared as "@Mai.Makes"
    /// and as "mai.makes" has to resolve to one person. A port of
    /// `handleValueKey`, and it has to stay one -- this is the key the server
    /// dedups on, so a mirror that folded differently would offer to attach a
    /// handle the server then refuses.
    static func valueKey(_ value: String) -> String {
        displayValue(value).lowercased()
    }

    var indexKey: String {
        "\(platform.trimmedLikeJS.lowercased())\u{0}\(Self.valueKey(value))"
    }
}

/// One person, as much of them as the sheet needs.
struct MirrorPerson: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let handles: [MirrorHandle]
}

/// The copy of the directory the share extension reads.
///
/// A cache, never the source of truth. The app rewrites it after every sync,
/// and it can be days stale if nobody has opened the app -- which is exactly
/// why the drain reconciles on the server instead of trusting what the sheet
/// decided from this.
///
/// Foundation only: this is compiled into the share extension.
struct DirectoryMirror: Codable, Equatable, Sendable {
    let refreshedAt: Date
    let people: [MirrorPerson]

    /// Who already holds this account, if anybody.
    ///
    /// The one question the mirror can answer with confidence, because
    /// (platform, handle) is exactly what the server keys on. A name match is
    /// a suggestion; this is an identity.
    func person(holding link: ProfileLink) -> MirrorPerson? {
        let wanted = MirrorHandle(platform: link.platform.rawValue, handle: link.handle)
            .indexKey
        return people.first { person in
            person.handles.contains { $0.indexKey == wanted }
        }
    }

    /// Everybody stored under this name, folded the way the server folds it.
    ///
    /// Everybody rather than the best one: two people really can share a name,
    /// and Haven never guesses two people are one. An empty name matches
    /// nobody, because "no guess" and "everybody" are different answers.
    func people(named name: String) -> [MirrorPerson] {
        let wanted = NameFold.normalize(name)
        guard !wanted.isEmpty else { return [] }
        return people.filter { NameFold.normalize($0.name) == wanted }
    }

    /// The sheet's search field: a partial name, because somebody typing "mai"
    /// has not finished typing.
    ///
    /// Answers in the order the app wrote them, which is the order
    /// `people:listPeople` returns -- most recently updated first. So when
    /// more people match than fit, the ones dropped are the ones the user has
    /// touched least recently.
    func search(_ query: String, limit: Int = 8) -> [MirrorPerson] {
        let needle = NameFold.normalize(query)
        guard !needle.isEmpty else { return [] }
        return people
            .filter { NameFold.normalize($0.name).contains(needle) }
            .prefix(limit)
            .map { $0 }
    }
}

extension MirrorHandle {
    /// The stored shape of a parsed share: the leading `@` is dropped so the
    /// value that renders and the value that dedups are one string, the same
    /// way `saveSharedProfile` stores it.
    init(platform: String, handle: String) {
        self.init(platform: platform, value: Self.displayValue(handle))
    }
}

/// Where the mirror lives in the App Group container.
///
/// Foundation only: this is compiled into the share extension.
struct DirectoryMirrorStore {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// The mirror both processes share, or nil when the App Group is not
    /// provisioned.
    static func inAppGroup() -> DirectoryMirrorStore? {
        guard let container = HavenAppGroup.containerURL else { return nil }
        return DirectoryMirrorStore(directory: container)
    }

    var fileURL: URL {
        directory.appendingPathComponent("directory-mirror.json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Replaces the mirror wholesale.
    ///
    /// Atomic, because the extension may be reading while the app writes, and
    /// a sheet that opened on half a file would show half a directory.
    func save(_ mirror: DirectoryMirror) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try Self.encoder.encode(mirror).write(to: fileURL, options: .atomic)
    }

    /// The mirror, or nil when there is not a readable one.
    ///
    /// Nil is an ordinary answer, not a failure: before the app has ever
    /// synced there is nothing here, and the sheet still has to open and still
    /// has to save.
    func load() -> DirectoryMirror? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(DirectoryMirror.self, from: data)
    }
}
