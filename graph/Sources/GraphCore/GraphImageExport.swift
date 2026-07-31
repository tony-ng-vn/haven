import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum GraphImageExportError: Error, Sendable {
    case couldNotCreateDestination
    case couldNotFinalize
}

/// Writes a CGImage to disk as PNG via ImageIO -- the same headless-testable layer
/// GraphImageRenderer uses, no AppKit/NSImage involved.
public enum GraphImageExport {
    public static func writePNG(image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            // The most common real-world cause: the containing directory does not exist, or
            // the path is otherwise unwritable. ImageIO reports this by returning nil here,
            // not by throwing, so this guard is the only place that failure surfaces.
            throw GraphImageExportError.couldNotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw GraphImageExportError.couldNotFinalize
        }
    }
}
