import ConvexMobile
import Foundation

/// The real drain target: the only part of the capture pipeline that touches
/// the network, and it lives in the app rather than the extension on purpose.
struct ConvexCaptureSink: EventCaptureSink {
    /// Where Instagram and X's own numeric ids come from. `var` with a
    /// default rather than `let`: a `let` with a default value is dropped
    /// from Swift's memberwise init entirely, which would make this
    /// unoverridable from any call site, tests included.
    var platformIds: PlatformIdResolving = LivePlatformIdResolving()

    func saveProfile(_ profile: QueuedCapture.Profile) async throws -> SharedProfileOutcome {
        try await saveShared(
            platform: profile.link.platform.rawValue,
            handleValue: profile.link.handle,
            profileUrl: profile.profileUrl,
            name: profile.name,
            note: profile.note,
            attachToPersonId: profile.attachToPersonId,
            // A shared profile carries neither: `source` is reserved for the
            // values only the server or a proven connection ever stamps, and
            // a fresh platformId is resolved fresh below, at drain time.
            source: nil,
            platformId: nil
        )
    }

    /// A person somebody typed out in the app, through the same mutation a
    /// share goes through.
    ///
    /// `people:addPerson` is the mutation written for this, and it is
    /// deliberately not the one called here. `saveSharedProfile` is idempotent
    /// on (platform, handle), which is the property a queued write actually
    /// needs: the drain can be killed between the mutation landing and the
    /// queue file being deleted, and the replay that follows has to answer
    /// "already" rather than file a second copy of somebody. It also folds a
    /// manual add into the person who already holds that handle, which is the
    /// same dedup the share sheet gets for free. Its platform argument is a
    /// free-form string, so WhatsApp and Telegram cost nothing.
    ///
    /// What it does not carry is company, role, city and a photo. Those belong
    /// to the person screen once the person exists; the add sheet asks for
    /// three fields on purpose.
    func saveManual(_ manual: QueuedCapture.Manual) async throws -> SharedProfileOutcome {
        try await saveShared(
            platform: manual.platform,
            // HavenShare queues a card's phone exactly as the card wrote it --
            // it has no PhoneNumberKit to normalize with. Here is where
            // PhoneNumberKit exists, so a second share of the same card folds
            // onto the same handle a hand-typed add already writes.
            handleValue: manual.platform == "phone"
                ? ContactValue.normalizedOrRaw(phone: manual.handleValue) : manual.handleValue,
            profileUrl: manual.profileUrl,
            name: manual.name,
            note: manual.note,
            attachToPersonId: manual.attachToPersonId,
            source: manual.source,
            platformId: manual.platformId
        )
    }

    /// Uploads the image and hands it to the existing capture pipeline, so a
    /// shared screenshot inherits extraction and its retries unchanged.
    func saveScreenshot(_ image: Data) async throws {
        try await saveScreenshot(image, event: nil)
    }

    func saveScreenshot(_ image: Data, event: EventReference) async throws {
        try await saveScreenshot(image, event: event as EventReference?)
    }

    private func saveScreenshot(_ image: Data, event: EventReference?) async throws {
        guard let contentType = ImageFormat.contentType(of: image) else {
            throw SinkError.notAnImage
        }
        let url: String = try await bounded { try await convex.mutation("captures:generateUploadUrl") }
        let storageId = try await PhotoUpload.send(image, to: url, contentType: contentType)
        var args: [String: ConvexEncodable?] = ["screenshotId": storageId]
        if let event { args["event"] = event.convexArgument }
        let _: String = try await bounded {
            try await convex.mutation("captures:createCapture", with: args)
        }
    }

    func link(_ event: EventReference, to personId: String) async throws {
        var args = event.convexArguments
        args["personId"] = personId
        let _: EventLinkOutcome = try await bounded {
            try await convex.mutation("events:linkPerson", with: args)
        }
    }

    private func saveShared(
        platform: String,
        handleValue: String,
        profileUrl: String,
        name: String,
        note: String?,
        attachToPersonId: String?,
        source: String?,
        platformId: String?
    ) async throws -> SharedProfileOutcome {
        // Neither id ever rides the queued capture -- the share extension
        // makes no network calls by design, so this is the first point in
        // the whole pipeline that could ever fetch one. Best-effort only: a
        // failed or slow lookup falls straight through to the save, it never
        // blocks it. This runs for a hand-typed Instagram or X add too, not
        // only a shared one -- `AddPersonDraft` offers both as manual
        // platforms, and both end up here.
        //
        // Resolved before the save, not after: `saveSharedProfile` looks its
        // handle up id-first, so a platformId has to be in hand by the time
        // this call is made for a rename to attach to the person who already
        // holds the account. An id fetched only after the save (the earlier
        // shape of this method) is too late to change which person the save
        // itself just wrote to.
        var resolvedPlatformId = platformId
        if resolvedPlatformId == nil {
            switch platform {
            case "instagram":
                resolvedPlatformId = await platformIds.instagramId(forHandle: handleValue)
            case "x":
                resolvedPlatformId = await platformIds.xId(forUsername: handleValue)
            default:
                break
            }
        }

        var args: [String: ConvexEncodable?] = [
            "platform": platform,
            "handleValue": handleValue,
            "profileUrl": profileUrl,
            "name": name,
        ]
        // Absent rather than null: the mutation's optionals mean "not given",
        // and an explicit null is a different thing to Convex.
        if let note { args["note"] = note }
        if let attachToPersonId { args["attachToPersonId"] = attachToPersonId }
        if let source { args["source"] = source }
        if let resolvedPlatformId { args["platformId"] = resolvedPlatformId }

        return try await bounded {
            try await convex.mutation("people:saveSharedProfile", with: args)
        }
    }

    /// Bounds one mutation the way every write elsewhere in the app is
    /// bounded: the client reconnects rather than failing, so an unbounded
    /// call on a dead connection would hang here forever. This file has no UI
    /// to say so -- a hang would stall `CaptureDrain`'s loop over the queue
    /// and, with it, `CaptureSync.isRunning` for the rest of the session,
    /// silently stopping every capture from draining until the app relaunches.
    /// A timeout throws instead, which the drain's own per-item `catch`
    /// already turns into "kept for next time".
    private func bounded<Value>(_ call: @escaping () async throws -> Value) async throws -> Value {
        let work = Task { try await call() }
        guard let value = await work.value(within: .seconds(HavenNetwork.deadline)) else {
            throw SinkError.timedOut
        }
        return value
    }

    enum SinkError: Error {
        case notAnImage
        case timedOut
    }
}

private struct EventLinkOutcome: Decodable {
    let status: String
    let eventId: String
}
