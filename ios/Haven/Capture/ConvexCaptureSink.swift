import ConvexMobile
import Foundation

/// The real drain target: the only part of the capture pipeline that touches
/// the network, and it lives in the app rather than the extension on purpose.
struct ConvexCaptureSink: CaptureSink {
    func saveProfile(_ profile: QueuedCapture.Profile) async throws -> SharedProfileOutcome {
        try await saveShared(
            platform: profile.link.platform.rawValue,
            handleValue: profile.link.handle,
            profileUrl: profile.profileUrl,
            name: profile.name,
            note: profile.note,
            attachToPersonId: profile.attachToPersonId
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
            handleValue: manual.handleValue,
            profileUrl: manual.profileUrl,
            name: manual.name,
            note: manual.note,
            attachToPersonId: manual.attachToPersonId
        )
    }

    /// Uploads the image and hands it to the existing capture pipeline, so a
    /// shared screenshot inherits extraction and its retries unchanged.
    func saveScreenshot(_ image: Data) async throws {
        guard let contentType = ImageFormat.contentType(of: image) else {
            throw SinkError.notAnImage
        }
        let url: String = try await convex.mutation("captures:generateUploadUrl")
        let storageId = try await PhotoUpload.send(image, to: url, contentType: contentType)
        let _: String = try await convex.mutation(
            "captures:createCapture",
            with: ["screenshotId": storageId]
        )
    }

    private func saveShared(
        platform: String,
        handleValue: String,
        profileUrl: String,
        name: String,
        note: String?,
        attachToPersonId: String?
    ) async throws -> SharedProfileOutcome {
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
        return try await convex.mutation("people:saveSharedProfile", with: args)
    }

    enum SinkError: Error {
        case notAnImage
    }
}
