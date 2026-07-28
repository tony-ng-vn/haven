import Foundation
import UniformTypeIdentifiers

/// Reads what the share sheet handed over.
///
/// A profile URL wins over an image when an app offers both, because an app
/// that shares a profile alongside its picture is sharing the profile. An
/// image on its own rides the existing screenshot pipeline instead.
enum ShareInput {
    static func read(
        _ items: [NSExtensionItem],
        storingImagesIn queue: CaptureQueue
    ) async -> ShareSubject? {
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
                continue
            }
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                let subject = ShareSubject(sharedURL: describe(url))
            {
                return subject
            }
        }

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                continue
            }
            if let fileName = await store(provider, in: queue) {
                return .screenshot(fileName: fileName)
            }
        }
        return nil
    }

    /// A shared URL arrives as an NSURL, and occasionally as the string of one.
    private static func describe(_ item: NSSecureCoding) -> String {
        if let url = item as? URL { return url.absoluteString }
        if let string = item as? String { return string }
        return ""
    }

    /// Copies a shared image into the container.
    ///
    /// The callback form rather than the async one on purpose: the file the
    /// system hands over is deleted the moment the callback returns, so the
    /// copy has to happen inside it.
    private static func store(
        _ provider: NSItemProvider,
        in queue: CaptureQueue
    ) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { url, _ in
                guard let url else { return continuation.resume(returning: nil) }
                continuation.resume(returning: try? queue.storeImage(copyingFrom: url))
            }
        }
    }
}
