import Foundation

/// One capture the extension took and the app has not sent yet.
///
/// The whole reason this type exists on disk: capture never fails. The sheet
/// writes here and closes, and whether there was a network, or a session, or a
/// signed-in user at that moment is the app's problem later.
struct QueuedCapture: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let payload: Payload

    enum Payload: Codable, Equatable, Sendable {
        case profile(Profile)
        case screenshot(Screenshot)
        case manual(Manual)
    }

    /// A shared profile URL, already parsed. Everything `saveSharedProfile`
    /// takes, so the drain is one call with nothing to work out.
    struct Profile: Codable, Equatable, Sendable {
        let link: ProfileLink
        let profileUrl: String
        let name: String
        /// The one line the sheet asked for. The only field no machine can
        /// ever fill, and on iOS the only way a memory gets created at all.
        let note: String?
        /// Who the user chose to add this platform to, when they chose. The
        /// mirror can be days stale, so the server treats this as a request
        /// rather than a fact.
        let attachToPersonId: String?
    }

    /// A shared image, copied into the container. The extension never uploads
    /// it -- the app's drain does, through the existing capture pipeline.
    struct Screenshot: Codable, Equatable, Sendable {
        let fileName: String
        let note: String?
    }

    /// Somebody typed into the app rather than shared in from another one.
    ///
    /// Its own case rather than `Profile`, because `ProfileLink` names one of
    /// the three platforms the share extension activates on, and a person you
    /// save by hand can carry any handle you want to record -- WhatsApp and
    /// Telegram included, per `mvp-design.md`.
    struct Manual: Codable, Equatable, Sendable {
        let name: String
        /// Free-form, and trimmed and folded by the server the same way every
        /// other handle write path is.
        let platform: String
        let handleValue: String
        /// The page this handle points at, or "" for a platform that has no
        /// web profile. The server keeps it as `link` and never overwrites one.
        let profileUrl: String
        /// Required at the moment of saving for a hand-typed add -- `AddPersonDraft`
        /// enforces that itself, the same way `handle` above is required there --
        /// but optional here because a card shared from Contacts carries no such
        /// bar: the name is the confirmation, and the note is exactly as
        /// optional as it is on a shared profile. Nil, never blank -- an empty
        /// string would still file a blank line in the person's context.
        let note: String?
        /// Who the user chose to add this to, when they chose. Same request,
        /// same staleness, same server-side resolution as a shared profile.
        let attachToPersonId: String?
        /// How this handle was captured -- "typed" for a hand-typed add from
        /// `AddPersonDraft`, "imported" for a vCard share or a Contacts
        /// import. Forwarded straight to `saveSharedProfile`; see
        /// `handleSourceValidator` in `convex/peopleFields.ts` for the full
        /// set of values, most of which iOS never stamps itself.
        let source: String?
        /// The platform's own numeric id, when the capture already carries
        /// one. Nothing that builds a `.manual` capture sets this today --
        /// Instagram and X ids are resolved at drain time instead, in
        /// `ConvexCaptureSink.saveShared` -- but the field exists here for
        /// the same reason `source` does: symmetry with what
        /// `saveSharedProfile` takes.
        let platformId: String?

        // A hand-written init rather than the synthesized memberwise one: a
        // `let` property with a default value is silently dropped from
        // Swift's memberwise init (there would be no parameter for it at
        // all), which would make `source`/`platformId` impossible to set
        // from any call site. Written out, both stay optional with a nil
        // default and every existing call site keeps compiling unchanged.
        init(
            name: String,
            platform: String,
            handleValue: String,
            profileUrl: String,
            note: String?,
            attachToPersonId: String?,
            source: String? = nil,
            platformId: String? = nil
        ) {
            self.name = name
            self.platform = platform
            self.handleValue = handleValue
            self.profileUrl = profileUrl
            self.note = note
            self.attachToPersonId = attachToPersonId
            self.source = source
            self.platformId = platformId
        }
    }
}

/// The pending captures in the App Group container.
///
/// One file per capture rather than one file holding a list. Two processes
/// write here, and a list would mean read-modify-write: the extension and the
/// app can each silently drop what the other just added, and one truncated
/// write loses everybody. A file per capture makes an interrupted write cost
/// exactly the capture that was being written.
///
/// Foundation only: this is compiled into the share extension.
struct CaptureQueue {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// The queue both processes share, or nil when the App Group is not
    /// provisioned -- which on a real device means the entitlement is missing
    /// from one of the two App IDs.
    static func inAppGroup() -> CaptureQueue? {
        guard let container = HavenAppGroup.containerURL else { return nil }
        return CaptureQueue(directory: container.appendingPathComponent("captures"))
    }

    /// Where the app writes a capture it made itself.
    ///
    /// The shared container when there is one, and the app's own otherwise.
    /// The fallback is not a nicety: saving somebody by hand writes here before
    /// it writes to Convex, and on a device where the group is missing from
    /// either App ID `inAppGroup` answers nil -- which would make the one
    /// operation the offline rule says can never fail, fail. The extension gets
    /// no such fallback, because a container the app cannot read is a capture
    /// nobody drains.
    static func forApp() -> CaptureQueue {
        inAppGroup() ?? inAppContainer()
    }

    /// Every queue the app should drain.
    ///
    /// The app's own container is always in the list, even when the group is
    /// there. A capture written while the group was missing sits in the
    /// private container, and would be stranded there for good once a later
    /// build provisions the group.
    static func drainable() -> [CaptureQueue] {
        guard let shared = inAppGroup() else { return [inAppContainer()] }
        return [shared, inAppContainer()]
    }

    private static func inAppContainer() -> CaptureQueue {
        CaptureQueue(
            directory: HavenAppGroup.appContainerURL.appendingPathComponent("captures")
        )
    }

    private var imagesDirectory: URL {
        directory.appendingPathComponent("images")
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

    // MARK: - Writing

    /// Writes a capture, creating the queue if this is the first one.
    ///
    /// Atomic, because the system kills a share extension the moment its sheet
    /// closes: a half-written file would be a capture that looks saved and is
    /// not.
    func enqueue(_ capture: QueuedCapture) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try Self.encoder.encode(capture).write(to: fileURL(for: capture.id), options: .atomic)
    }

    /// Copies an image into the container and answers the name to record.
    ///
    /// Copied rather than referenced: the sending app can revoke its own file
    /// as soon as the sheet closes, and the drain runs long after that.
    func storeImage(copyingFrom source: URL) throws -> String {
        try FileManager.default.createDirectory(
            at: imagesDirectory, withIntermediateDirectories: true
        )
        let fileName = "\(UUID().uuidString).\(source.pathExtension)"
        try FileManager.default.copyItem(
            at: source, to: imagesDirectory.appendingPathComponent(fileName)
        )
        return fileName
    }

    // MARK: - Reading

    /// Every capture waiting, oldest first.
    ///
    /// Oldest first because replay order decides the outcome: a second share
    /// of one account appends its note to the person the first one created,
    /// and the other order would file the notes under the wrong share.
    ///
    /// A file that will not decode is skipped rather than thrown, so one bad
    /// capture never holds the rest of the queue hostage.
    func pending() -> [QueuedCapture] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? Self.decoder.decode(QueuedCapture.self, from: data)
            }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Where a stored image lives.
    ///
    /// The name comes back off disk, so it is treated as untrusted: only the
    /// last path component is used, and a name carrying `..` cannot reach
    /// outside the container.
    func imageURL(named fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(
            (fileName as NSString).lastPathComponent
        )
    }

    // MARK: - Draining

    /// Forgets a capture that has landed, image and all.
    ///
    /// Deleting what is already gone is not an error: the drain can be killed
    /// between the mutation and this call, and the replay that follows is the
    /// design working, not a fault.
    func remove(_ capture: QueuedCapture) throws {
        if case .screenshot(let screenshot) = capture.payload {
            // An image left behind is a leak nobody can see, in a container
            // with a quota.
            try? FileManager.default.removeItem(at: imageURL(named: screenshot.fileName))
        }
        let url = fileURL(for: capture.id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
