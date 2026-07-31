import XCTest
import CoreGraphics
import ImageIO
@testable import GraphCore

final class GraphImageExportTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphImageExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeTestImage(width: Int = 12, height: Int = 8) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("could not create a test bitmap context")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let image = context.makeImage() else {
            fatalError("could not rasterize the test bitmap context")
        }
        return image
    }

    func testWritesADecodablePNGWithCorrectDimensions() throws {
        let image = makeTestImage(width: 12, height: 8)
        let url = tempDirectory.appendingPathComponent("export.png")

        try GraphImageExport.writePNG(image: image, to: url)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("the written file must decode back as an image")
        }
        XCTAssertEqual(decoded.width, 12)
        XCTAssertEqual(decoded.height, 8)
    }

    func testPropagatesFailureForAnUnwritablePath() {
        let image = makeTestImage()
        // A directory that does not exist and is never created: ImageIO cannot write here.
        let url = tempDirectory
            .appendingPathComponent("does-not-exist", isDirectory: true)
            .appendingPathComponent("export.png")

        XCTAssertThrowsError(try GraphImageExport.writePNG(image: image, to: url))
    }
}
