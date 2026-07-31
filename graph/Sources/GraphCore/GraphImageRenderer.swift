import Foundation
import CoreGraphics
import CoreText

/// Renders a rest-state (never focus-dimmed) snapshot of a Graph to a bitmap, pure Core
/// Graphics so it is fully testable headlessly with `swift test` -- no SwiftUI ImageRenderer,
/// no launched app. Screen and export share edge/node selection logic (EdgeRenderList,
/// Graph.excludingNodes) and color values (NodePalette): this file's only real job is turning
/// that already-tested data into pixels.
///
/// Coordinate convention: `positions`/`canvasSize` are top-left-origin, y-down, exactly like
/// the values GraphView already draws with inside a SwiftUI Canvas. A raw CGContext is
/// bottom-left-origin, y-up, so every point drawn here is flipped once in Swift (`flip(_:)`)
/// rather than via a CTM transform -- a CTM-level flip would also mirror Core Text's glyphs,
/// forcing an extra per-label counter-flip; flipping the coordinates themselves keeps text
/// upright for free and needs no compensating trick.
public enum GraphImageRenderer {
    public static func render(
        graph: Graph,
        positions: [String: CGPoint],
        radii: [String: CGFloat],
        hiddenNodeIDs: Set<String>,
        canvasSize: CGSize,
        scale: CGFloat = 3,
        guesses: [String: NameGuess] = [:]
    ) -> CGImage {
        // Non-finite or non-positive input would otherwise trap converting to Int below (a
        // real caller never passes this, but a defensive floor costs nothing).
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let safeWidth = canvasSize.width.isFinite && canvasSize.width > 0 ? canvasSize.width : 1
        let safeHeight = canvasSize.height.isFinite && canvasSize.height > 0 ? canvasSize.height : 1
        let pixelWidth = max(1, Int((safeWidth * safeScale).rounded()))
        let pixelHeight = max(1, Int((safeHeight * safeScale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("GraphImageRenderer: failed to create a \(pixelWidth)x\(pixelHeight) bitmap context")
        }

        // Every drawing call below uses LOGICAL (unscaled, canvasSize-sized) coordinates; this
        // one scale bakes the resolution multiplier into the CTM instead of every call site
        // multiplying its own points by `scale`.
        context.scaleBy(x: safeScale, y: safeScale)

        let logicalHeight = safeHeight

        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: logicalHeight - point.y)
        }

        // Background fill, full canvas.
        let background = NodePalette.background
        context.setFillColor(cgColor(background, in: colorSpace))
        context.fill(CGRect(x: 0, y: 0, width: safeWidth, height: safeHeight))

        let visibleGraph = graph.excludingNodes(hiddenNodeIDs)

        drawEdges(into: context, visibleGraph: visibleGraph, positions: positions, colorSpace: colorSpace, flip: flip)
        drawNodes(into: context, visibleGraph: visibleGraph, positions: positions, radii: radii, guesses: guesses, colorSpace: colorSpace, flip: flip)

        guard let image = context.makeImage() else {
            preconditionFailure("GraphImageRenderer: failed to rasterize the bitmap context")
        }
        return image
    }

    /// Builds a CGColor in the SAME color space as the bitmap context: CGColor(red:green:
    /// blue:alpha:), used naively, constructs a color in the generic/extended sRGB space,
    /// which CG then converts on fill -- shifting stored byte values away from a naive
    /// round(component * 255) by several percent (found the hard way, from a failing pixel
    /// probe test). Explicitly matching color spaces makes stored bytes predictable, which
    /// the test suite's exact-color assertions depend on.
    private static func cgColor(_ color: RGBAColor, in colorSpace: CGColorSpace) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [color.red, color.green, color.blue, color.alpha]) ?? CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    /// Exactly the screen's rest-state edge selection and opacity formula (GraphView.drawEdges):
    /// EdgeRenderList already excludes involvesUser edges and edges to an unpositioned (dead,
    /// unincluded) node; Graph.excludingNodes(hiddenNodeIDs), applied by the caller before this
    /// is reached, is what makes a hidden node's edges vanish too, for free.
    private static func drawEdges(
        into context: CGContext,
        visibleGraph: Graph,
        positions: [String: CGPoint],
        colorSpace: CGColorSpace,
        flip: (CGPoint) -> CGPoint
    ) {
        let edgeColor = NodePalette.edge
        for edge in EdgeRenderList.visibleEdges(graph: visibleGraph, positions: positions) {
            let opacity = min(1.0, 0.08 + 0.12 * (edge.strength + 1).squareRoot())
            context.setStrokeColor(cgColor(RGBAColor(red: edgeColor.red, green: edgeColor.green, blue: edgeColor.blue, alpha: opacity), in: colorSpace))
            context.setLineWidth(0.75)
            context.beginPath()
            context.move(to: flip(edge.from))
            context.addLine(to: flip(edge.to))
            context.strokePath()
        }
    }

    private static func drawNodes(
        into context: CGContext,
        visibleGraph: Graph,
        positions: [String: CGPoint],
        radii: [String: CGFloat],
        guesses: [String: NameGuess],
        colorSpace: CGColorSpace,
        flip: (CGPoint) -> CGPoint
    ) {
        for node in visibleGraph.nodes {
            guard let position = positions[node.id], let radius = radii[node.id] else { continue }
            let center = flip(position)
            let color = NodePalette.color(for: node.kind)
            context.setFillColor(cgColor(color, in: colorSpace))
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: rect)

            // Every visible node that HAS a name OR a cached guess gets a label drawn --
            // unlike the screen, this is never budget-limited to the top 40 (LabelBudget):
            // export is the definitive, "real names (or visibly-marked guesses)" artifact
            // PLAN.md describes, not an interactive-readability view. NodeLabel is the single
            // shared rule (real name wins, guess is tilde-prefixed, nil otherwise) with the
            // screen (GraphView), so the two can never disagree on what a label says.
            guard let label = NodeLabel.resolve(node: node, guesses: guesses) else { continue }
            drawLabel(label, at: CGPoint(x: center.x + radius + 4, y: center.y), in: context, colorSpace: colorSpace)
        }
    }

    /// Baseline-anchored at `point` (unlike the screen's vertically-centered SwiftUI Text
    /// anchor): a small cosmetic difference from the on-screen label position, not tested by
    /// pixel-exact placement, only by "ink appears somewhere in the region right of the node".
    private static func drawLabel(_ text: String, at point: CGPoint, in context: CGContext, colorSpace: CGColorSpace) {
        let label = NodePalette.label
        let textColor = cgColor(label, in: colorSpace)
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        // Pure CoreText attribute keys, not NSAttributedString.Key.font/.foregroundColor:
        // those AppKit-provided aliases would pull in an AppKit dependency GraphCore does
        // not otherwise have, just for two attribute names.
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let attributedString = NSAttributedString(
            string: text,
            attributes: [fontKey: font, colorKey: textColor]
        )
        let line = CTLineCreateWithAttributedString(attributedString)

        context.saveGState()
        // Belt and suspenders: CTLineDraw falls back to the context's current fill color for
        // any glyph that does not resolve an explicit color attribute.
        context.setFillColor(textColor)
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
