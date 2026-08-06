import Foundation
import UniformTypeIdentifiers

/// Reads what the share sheet handed over.
///
/// A vCard wins over everything else: Contacts' own "Share Contact" hands
/// over nothing but one, and there is no other case where a card competes
/// with a URL, a message or an image for what the share actually means. Below
/// that, a profile URL wins over a text message, which wins over an image,
/// when an app offers more than one: an app that shares a profile alongside
/// its picture is sharing the profile, and a URL attachment is a link Haven
/// does not have to go find inside a sentence first. An image on its own
/// rides the existing screenshot pipeline instead.
enum ShareInput {
    static func read(
        _ items: [NSExtensionItem],
        storingImagesIn queue: CaptureQueue
    ) async -> ShareSubject? {
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.vCard.identifier) else {
                continue
            }
            if let data = await loadVCardData(provider), let subject = ShareSubject(vCard: data) {
                return subject
            }
        }

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

        // LinkedIn's own app shares a profile this way: a message with the
        // link inside it, never a URL attachment at all. ShareSubject owns
        // deciding what counts as a profile link; this only hands it more
        // than one candidate string to try.
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else {
                continue
            }
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                let subject = ShareSubject(embeddedInText: describe(text))
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

    /// A shared URL arrives as an NSURL, and occasionally as the string of
    /// one; a shared message arrives as a string already. Both passes read
    /// through this, so neither has to know which.
    private static func describe(_ item: NSSecureCoding) -> String {
        if let url = item as? URL { return url.absoluteString }
        if let string = item as? String { return string }
        return ""
    }

    /// Bytes for a vCard attachment, however the sender backs it -- data in
    /// memory from Contacts, or a file on disk from Files. The data form
    /// rather than `loadItem`'s NSURL: that URL points at a sandboxed temp
    /// file the system can reclaim once this call returns, the same reason
    /// `store` below never lets a shared image round-trip through one either.
    private static func loadVCardData(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.vCard.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
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
