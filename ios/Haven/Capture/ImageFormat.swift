import Foundation

/// What kind of image some bytes are.
///
/// Read from the bytes rather than the file name, because the name came out of
/// whatever app did the sharing and can be absent or wrong. Convex stores the
/// content type the upload declares, so a PNG announced as a JPEG is a lie
/// that outlives the upload.
enum ImageFormat {
    /// The MIME type to declare when uploading, or nil when these bytes are
    /// not an image Haven recognizes.
    static func contentType(of data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        // HEIC and WebP both carry their marker after a four-byte length or
        // magic, so the brand is at offset 8 rather than 0.
        guard data.count >= 12 else { return nil }
        let brand = data[8..<12]
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), brand.elementsEqual([0x57, 0x45, 0x42, 0x50]) {
            return "image/webp"
        }
        if brand.elementsEqual([0x68, 0x65, 0x69, 0x63])
            || brand.elementsEqual([0x68, 0x65, 0x69, 0x66])
            || brand.elementsEqual([0x6D, 0x69, 0x66, 0x31])
        {
            return "image/heic"
        }
        return nil
    }
}
