import XCTest
@testable import GraphCore

final class HitTestTests: XCTestCase {

    private func assertPointsEqual(
        _ a: CGPoint,
        _ b: CGPoint,
        _ message: String = "",
        accuracy: CGFloat = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
    }

    // MARK: - Transform round-trip

    func testCanvasPointRoundTripsThroughTheForwardTransformAtIdentity() {
        let canvasSize = CGSize(width: 800, height: 600)
        let original = CGPoint(x: 123, y: 456)
        let transform = HitTest.canvasToScreenTransform(canvasSize: canvasSize, scale: 1.0, offset: .zero)
        let screenPoint = original.applying(transform)

        let recovered = HitTest.canvasPoint(screenPoint: screenPoint, canvasSize: canvasSize, scale: 1.0, offset: .zero)

        assertPointsEqual(recovered, original)
    }

    func testCanvasPointRoundTripsThroughAScaledAndOffsetTransform() {
        let canvasSize = CGSize(width: 800, height: 600)
        let scale: CGFloat = 2.5
        let offset = CGSize(width: -40, height: 75)
        let original = CGPoint(x: 300, y: 100)

        let transform = HitTest.canvasToScreenTransform(canvasSize: canvasSize, scale: scale, offset: offset)
        let screenPoint = original.applying(transform)
        let recovered = HitTest.canvasPoint(screenPoint: screenPoint, canvasSize: canvasSize, scale: scale, offset: offset)

        assertPointsEqual(recovered, original)
    }

    /// The canvas center itself must map to (center + offset) in screen space: scale alone
    /// never moves the center, only offset does. This is the assertion that would catch a
    /// transposed sign or a wrong anchor point in the forward transform.
    func testCenterMapsToCenterPlusOffsetRegardlessOfScale() {
        let canvasSize = CGSize(width: 800, height: 600)
        let center = CGPoint(x: 400, y: 300)
        let offset = CGSize(width: 50, height: -20)

        for scale: CGFloat in [0.5, 1.0, 3.0] {
            let transform = HitTest.canvasToScreenTransform(canvasSize: canvasSize, scale: scale, offset: offset)
            let screenPoint = center.applying(transform)
            assertPointsEqual(screenPoint, CGPoint(x: 450, y: 280), "scale=\(scale)")
        }
    }

    // MARK: - nodeID search

    func testPicksTheNearestNodeWithinItsHitRadius() {
        let positions: [String: CGPoint] = [
            "near": CGPoint(x: 100, y: 100),
            "far": CGPoint(x: 500, y: 500),
        ]
        let radii: [String: CGFloat] = ["near": 10, "far": 10]

        let hitID = HitTest.nodeID(
            atScreenPoint: CGPoint(x: 103, y: 100),
            canvasSize: CGSize(width: 800, height: 600),
            scale: 1.0,
            offset: .zero,
            positions: positions,
            radii: radii
        )

        XCTAssertEqual(hitID, "near")
    }

    func testReturnsNilWhenNothingIsWithinReach() {
        let positions: [String: CGPoint] = ["only": CGPoint(x: 100, y: 100)]
        let radii: [String: CGFloat] = ["only": 5]

        let hitID = HitTest.nodeID(
            atScreenPoint: CGPoint(x: 300, y: 300),
            canvasSize: CGSize(width: 800, height: 600),
            scale: 1.0,
            offset: .zero,
            positions: positions,
            radii: radii
        )

        XCTAssertNil(hitID)
    }

    func testMinimumHitRadiusAppliesEvenWhenTheNodesOwnRadiusIsSmaller() {
        // A tiny 1pt-radius node: without the minimum floor a click 6pt away would miss it.
        let positions: [String: CGPoint] = ["tiny": CGPoint(x: 100, y: 100)]
        let radii: [String: CGFloat] = ["tiny": 1]

        let hitID = HitTest.nodeID(
            atScreenPoint: CGPoint(x: 106, y: 100),
            canvasSize: CGSize(width: 800, height: 600),
            scale: 1.0,
            offset: .zero,
            positions: positions,
            radii: radii,
            minimumHitRadius: 8
        )

        XCTAssertEqual(hitID, "tiny")
    }

    func testTiesAreBrokenByIDAscending() {
        // Both nodes exactly 5pt from the click point, both within radius: must not depend
        // on Dictionary iteration order.
        let positions: [String: CGPoint] = [
            "zeta": CGPoint(x: 95, y: 100),
            "alpha": CGPoint(x: 105, y: 100),
        ]
        let radii: [String: CGFloat] = ["zeta": 10, "alpha": 10]

        let hitID = HitTest.nodeID(
            atScreenPoint: CGPoint(x: 100, y: 100),
            canvasSize: CGSize(width: 800, height: 600),
            scale: 1.0,
            offset: .zero,
            positions: positions,
            radii: radii
        )

        XCTAssertEqual(hitID, "alpha")
    }

    /// The one test that would catch the transform and the search disagreeing with each
    /// other: a node placed at a known canvas position, clicked at its *screen* position
    /// under a non-trivial scale+offset, must still resolve to that node.
    func testHitTestingWorksThroughANonTrivialScaleAndOffset() {
        let canvasSize = CGSize(width: 800, height: 600)
        let scale: CGFloat = 2.0
        let offset = CGSize(width: 30, height: -50)
        let nodeCanvasPosition = CGPoint(x: 250, y: 350)
        let positions: [String: CGPoint] = ["node": nodeCanvasPosition]
        let radii: [String: CGFloat] = ["node": 6]

        let transform = HitTest.canvasToScreenTransform(canvasSize: canvasSize, scale: scale, offset: offset)
        let screenPointOverNode = nodeCanvasPosition.applying(transform)

        let hitID = HitTest.nodeID(
            atScreenPoint: screenPointOverNode,
            canvasSize: canvasSize,
            scale: scale,
            offset: offset,
            positions: positions,
            radii: radii
        )

        XCTAssertEqual(hitID, "node")
    }
}
