import ConvexMobile
import Foundation

/// The real drain target: the only part of the capture pipeline that touches
/// the network, and it lives in the app rather than the extension on purpose.
struct ConvexCaptureSink: CaptureSink {
    func saveProfile(_ profile: QueuedCapture.Profile) async throws -> SharedProfileOutcome {
        var args: [String: ConvexEncodable?] = [
            "platform": profile.link.platform.rawValue,
            "handleValue": profile.link.handle,
            "profileUrl": profile.profileUrl,
            "name": profile.name,
        ]
        // Absent rather than null: the mutation's optionals mean "not given",
        // and an explicit null is a different thing to Convex.
        if let note = profile.note { args["note"] = note }
        if let attachToPersonId = profile.attachToPersonId {
            args["attachToPersonId"] = attachToPersonId
        }
        return try await convex.mutation("people:saveSharedProfile", with: args)
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

    enum SinkError: Error {
        case notAnImage
    }
}
