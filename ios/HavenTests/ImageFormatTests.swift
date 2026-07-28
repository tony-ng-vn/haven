import Foundation
import Testing
@testable import Haven

/// Real file headers, followed by enough filler to clear the 12-byte floor the
/// container formats need.
private func header(_ bytes: [UInt8]) -> Data {
    Data(bytes + Array(repeating: 0, count: max(0, 16 - bytes.count)))
}

@Suite("Reading an image's format from its bytes")
struct ImageFormatTests {
    // Convex stores the content type an upload declares, so a PNG announced as
    // a JPEG is a lie that outlives the upload. Screenshots are usually PNG
    // and photos usually HEIC, so guessing one default would be wrong most of
    // the time either way.
    @Test("each format is recognized by its own magic")
    func formats() {
        #expect(ImageFormat.contentType(of: header([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) == "image/png")
        #expect(ImageFormat.contentType(of: header([0xFF, 0xD8, 0xFF, 0xE0])) == "image/jpeg")
        #expect(ImageFormat.contentType(of: header([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) == "image/gif")
        // RIFF....WEBP -- the brand sits after the four-byte length.
        #expect(
            ImageFormat.contentType(
                of: header([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])
            ) == "image/webp"
        )
        // ....ftypheic, which is what an iPhone screenshot of a photo can be.
        #expect(
            ImageFormat.contentType(
                of: header([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
            ) == "image/heic"
        )
    }

    // Nil rather than a guess: the server refuses a blob that is not an image,
    // and declaring one anyway turns a clear refusal into a stored lie.
    @Test("anything else is not an image")
    func notAnImage() {
        #expect(ImageFormat.contentType(of: Data("not an image at all".utf8)) == nil)
        #expect(ImageFormat.contentType(of: Data()) == nil)
        // Truncated below the twelve bytes a container brand needs.
        #expect(ImageFormat.contentType(of: Data([0, 0, 0, 0x18, 0x66, 0x74])) == nil)
    }
}
