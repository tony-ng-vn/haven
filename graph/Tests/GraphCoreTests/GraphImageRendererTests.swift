import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import GraphCore

final class GraphImageRendererTests: XCTestCase {

    // MARK: - Pixel probing helper (the brief asks for exactly one)

    private func pixel(of image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard let data = image.dataProvider?.data, let pointer = CFDataGetBytePtr(data) else {
            XCTFail("no pixel data")
            return (0, 0, 0, 0)
        }
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * bytesPerRow + x * bytesPerPixel
        return (pointer[offset], pointer[offset + 1], pointer[offset + 2], pointer[offset + 3])
    }

    /// CG rounding of a 0...1 component to a byte, matching what CGContext itself does when
    /// filling an opaque shape -- used with a small tolerance, not exact equality, since AA
    /// and color-space conversion can round the last bit differently.
    private func expectedByte(_ component: Double) -> UInt8 {
        UInt8((component * 255).rounded())
    }

    private func assertByte(_ actual: UInt8, matches expected: Double, tolerance: UInt8 = 2, file: StaticString = #filePath, line: UInt = #line) {
        let expectedByte = expectedByte(expected)
        let diff = actual > expectedByte ? actual - expectedByte : expectedByte - actual
        XCTAssertLessThanOrEqual(diff, tolerance, "byte \(actual) not within \(tolerance) of expected \(expectedByte)", file: file, line: line)
    }

    private func regionHasInk(image: CGImage, xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) -> Bool {
        for y in yRange {
            for x in xRange {
                let p = pixel(of: image, x: x, y: y)
                if p.r != 0 || p.g != 0 || p.b != 0 {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Fixture

    private func node(id: String, kind: NodeKind, name: String?) -> GraphNode {
        GraphNode(id: id, kind: kind, name: name, thumbnailImageData: nil, hasContactCard: name != nil, isLive: true, degree: 1)
    }

    private func edge(_ a: String, _ b: String, strength: Double) -> GraphEdge {
        GraphEdge(nodeIDA: a, nodeIDB: b, source: .imessage, reason: .groupMembership, strength: strength, involvesUser: false)
    }

    private let canvasSize = CGSize(width: 700, height: 500)

    /// Nodes placed far apart, per the brief, so label/edge/hidden regions never overlap:
    /// alice (named) and bob (unnamed) sit on the same horizontal band for the label test;
    /// carol sits far below, connected to bob, for the hidden-node-and-its-edge test.
    private func fixtureGraph() -> Graph {
        Graph(
            nodes: [
                node(id: "user", kind: .user, name: nil),
                // Deliberately a very short name: if drawLabel ever drew node.id (a phone
                // number) instead of node.name, or drew a fixed placeholder, this alone
                // wouldn't catch it -- see "eve" below, which is what actually pins content.
                node(id: "alice", kind: .person, name: "Al"),
                node(id: "bob", kind: .person, name: nil),
                node(id: "carol", kind: .person, name: "Carol Hidden"),
                node(id: "eve", kind: .person, name: "Alexandra Wintermute"),
            ],
            edges: [
                edge("alice", "bob", strength: 3),
                edge("carol", "bob", strength: 2),
            ]
        )
    }

    private let positions: [String: CGPoint] = [
        "user": CGPoint(x: 350, y: 30),
        "alice": CGPoint(x: 120, y: 250),
        "bob": CGPoint(x: 450, y: 250),
        "carol": CGPoint(x: 120, y: 450),
        "eve": CGPoint(x: 120, y: 150),
    ]

    private let radii: [String: CGFloat] = [
        "user": 6,
        "alice": 20,
        "bob": 20,
        "carol": 15,
        "eve": 20,
    ]

    // MARK: - Tests

    func testImageDimensionsEqualCanvasSizeTimesScale() {
        let image = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 3
        )

        XCTAssertEqual(image.width, Int(canvasSize.width * 3))
        XCTAssertEqual(image.height, Int(canvasSize.height * 3))
    }

    func testBackgroundCornerAndNodeCenterPixelsMatchThePalette() {
        let image = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 1
        )

        // Far corner, nowhere near any node: pure background.
        let corner = pixel(of: image, x: 10, y: 10)
        assertByte(corner.r, matches: NodePalette.background.red)
        assertByte(corner.g, matches: NodePalette.background.green)
        assertByte(corner.b, matches: NodePalette.background.blue)

        // Node centers are fully covered by the fill, so AA at the rim cannot affect them.
        let aliceCenter = pixel(of: image, x: 120, y: 250)
        let personColor = NodePalette.color(for: .person)
        assertByte(aliceCenter.r, matches: personColor.red)
        assertByte(aliceCenter.g, matches: personColor.green)
        assertByte(aliceCenter.b, matches: personColor.blue)
    }

    /// Pins the exact screen formula (GraphView.drawEdges: `min(1.0, 0.08 + 0.12 *
    /// sqrt(strength + 1))`), not just "some dimming happens": a bug that dropped alpha
    /// entirely (drawing every edge at full strength) would still pass a bare
    /// "differs from background" check.
    func testEdgeOpacityMatchesTheScreenSSqrtStrengthFormula() {
        // Rendered at scale 3: a 0.75pt line is under a pixel wide at scale 1, so the exact
        // geometric-midpoint pixel can land partly outside the stroke's AA coverage and read
        // artificially dim (found the hard way: the scale-1 version of this test failed at a
        // value far below the expected one, purely from sub-pixel coverage, not a real bug).
        // At scale 3 the stroke is ~2.25px wide, so scanning a small perpendicular window and
        // taking the best-covered sample reliably lands on a fully-covered pixel.
        let image = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 3
        )

        // alice(120,250) <-> bob(450,250), strength 3: expected opacity 0.08 + 0.12*sqrt(4) = 0.32.
        let midX = Int((120 + 450) / 2 * 3)
        let samples = (745...755).map { pixel(of: image, x: midX, y: $0) }
        let peak = samples.max { $0.r < $1.r }!

        let expectedOpacity = min(1.0, 0.08 + 0.12 * (3.0 + 1).squareRoot())
        assertByte(peak.r, matches: expectedOpacity, tolerance: 6)
        assertByte(peak.g, matches: expectedOpacity, tolerance: 6)
        assertByte(peak.b, matches: expectedOpacity, tolerance: 6)
        XCTAssertLessThan(peak.r, 200, "a strength-3 edge must be visibly dimmer than full white, not drawn at full alpha")
    }

    /// Distinguishes "the label draws SOMETHING" (which a bug that drew node.id, or a fixed
    /// placeholder, would also satisfy) from "the label draws the node's actual name": a
    /// very short and a very long name should reach very different distances to the right.
    func testLabelInkTracksTheActualNameContentNotJustItsPresence() {
        let image = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 1
        )

        // A band far enough right of the node that "Al" (empirically ~8pt wide at this font/
        // size) cannot possibly reach it, but "Alexandra Wintermute" (empirically still
        // inked past x=240) should.
        let farBandXRange = 190...210

        // y 240...248, not 240...260: the alice<->bob edge runs exactly through y=250 on its
        // way to bob, and probing through it would find ink that has nothing to do with the
        // label -- exactly the false positive this test hit before this range was narrowed.
        let aliceFarBand = regionHasInk(image: image, xRange: farBandXRange, yRange: 240...248)
        XCTAssertFalse(aliceFarBand, "a two-character name should not reach 70pt past the node")

        let eveFarBand = regionHasInk(image: image, xRange: farBandXRange, yRange: 140...148)
        XCTAssertTrue(eveFarBand, "a 20-character name should reach a band a two-character name cannot")
    }

    func testHiddenNodeCenterIsBackgroundAndItsEdgeToItsNeighborIsGone() {
        let midpoint = (x: (120 + 450) / 2, y: (450 + 250) / 2) // carol <-> bob

        // Control: with nothing hidden, carol's center and the carol-bob edge midpoint both
        // have real ink -- otherwise the "background after hiding" assertion below would be
        // vacuously true regardless of whether hiding actually did anything.
        let visibleImage = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 1
        )
        let carolCenterVisible = pixel(of: visibleImage, x: 120, y: 450)
        XCTAssertTrue(carolCenterVisible.r != 0 || carolCenterVisible.g != 0 || carolCenterVisible.b != 0, "control: carol should be drawn when not hidden")
        let midpointVisible = pixel(of: visibleImage, x: midpoint.x, y: midpoint.y)
        XCTAssertTrue(midpointVisible.r != 0 || midpointVisible.g != 0 || midpointVisible.b != 0, "control: the carol-bob edge should be drawn when not hidden")

        let hiddenImage = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: ["carol"], canvasSize: canvasSize, scale: 1
        )
        let carolCenterHidden = pixel(of: hiddenImage, x: 120, y: 450)
        XCTAssertEqual(carolCenterHidden.r, 0)
        XCTAssertEqual(carolCenterHidden.g, 0)
        XCTAssertEqual(carolCenterHidden.b, 0)
        let midpointHidden = pixel(of: hiddenImage, x: midpoint.x, y: midpoint.y)
        XCTAssertEqual(midpointHidden.r, 0)
        XCTAssertEqual(midpointHidden.g, 0)
        XCTAssertEqual(midpointHidden.b, 0)
    }

    func testNamedNodeGetsALabelUnnamedNodeDoesNot() {
        let image = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 1
        )

        // Alice (named, radius 20, center x=120): label region starts just past the rim.
        let aliceHasInk = regionHasInk(image: image, xRange: 142...180, yRange: 240...260)
        XCTAssertTrue(aliceHasInk, "a named node should have label ink to its right")

        // Bob (unnamed, radius 20, center x=450): the equivalent region must stay background.
        let bobHasInk = regionHasInk(image: image, xRange: 472...510, yRange: 240...260)
        XCTAssertFalse(bobHasInk, "an unnamed node must not get a label")
    }

    func testDeterministicOutputAcrossTwoRenders() {
        let imageA = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 2
        )
        let imageB = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 2
        )

        // Strongest check: the raw bitmap buffers, byte for byte.
        guard let dataA = imageA.dataProvider?.data, let dataB = imageB.dataProvider?.data else {
            return XCTFail("missing pixel data")
        }
        XCTAssertEqual(dataA as Data, dataB as Data, "identical input must produce byte-identical pixel buffers")

        // Also the brief's literal ask: two PNG encodes of the same pixels, byte-identical.
        XCTAssertEqual(pngData(for: imageA), pngData(for: imageB), "identical input must produce byte-identical PNG data")
    }

    func testScale1VersusScale3DimensionRatio() {
        let scale1 = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 1
        )
        let scale3 = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 3
        )

        XCTAssertEqual(scale3.width, scale1.width * 3)
        XCTAssertEqual(scale3.height, scale1.height * 3)
    }

    /// The step-7 wiring: export shows tilde-marked guesses too (PLAN.md), for a node with no
    /// real name. bob (unnamed, no edge extends past his position at x=450) is the subject:
    /// no guess -> no label at all; a guess for his key -> a label now renders. This proves
    /// the wiring (GraphImageRenderer actually consults `guesses`), not the string format
    /// itself -- NodeLabelTests already pins the exact "~name" text precisely.
    func testCachedGuessRendersALabelForAnUnnamedNodeThatHadNoneBefore() {
        let bobLabelXRange = 474...510
        let bobLabelYRange = 240...248 // avoids the alice<->bob edge's y=250, same as elsewhere in this file

        let withoutGuess = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 1
        )
        XCTAssertFalse(
            regionHasInk(image: withoutGuess, xRange: bobLabelXRange, yRange: bobLabelYRange),
            "an unnamed node with no cached guess must show no label at all in export, same as before this step"
        )

        let withGuess = GraphImageRenderer.render(
            graph: fixtureGraph(), positions: positions, radii: radii,
            hiddenNodeIDs: [], canvasSize: canvasSize, scale: 1,
            guesses: ["bob": NameGuess(name: "Bo")]
        )
        XCTAssertTrue(
            regionHasInk(image: withGuess, xRange: bobLabelXRange, yRange: bobLabelYRange),
            "a cached guess for an unnamed node must now draw a label in export"
        )
    }

    private func pngData(for image: CGImage) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            XCTFail("could not create PNG destination")
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
