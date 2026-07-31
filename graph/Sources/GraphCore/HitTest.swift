import Foundation
import CoreGraphics

/// Screen-space hit testing against a settled/settling simulation's node positions. The one
/// piece of new interaction logic that cannot be verified by launching the app (off limits
/// in this project), so it is pulled out of the view and unit tested here instead: this is
/// the single source of truth for both the forward draw transform (GraphView.draw uses
/// `canvasToScreenTransform` via GraphicsContext.concatenate) and its inverse (used here),
/// so the two can never drift apart from each other.
public enum HitTest {
    /// Scale is anchored at the canvas center; offset is a plain post-scale screen-space
    /// translation. Matches exactly what GraphView applies before drawing.
    public static func canvasToScreenTransform(canvasSize: CGSize, scale: CGFloat, offset: CGSize) -> CGAffineTransform {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        // screen = center + scale*(canvasPoint - center) + offset
        //        = scale*canvasPoint + (center*(1-scale) + offset)
        let tx = center.x * (1 - scale) + offset.width
        let ty = center.y * (1 - scale) + offset.height
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)
    }

    public static func canvasPoint(screenPoint: CGPoint, canvasSize: CGSize, scale: CGFloat, offset: CGSize) -> CGPoint {
        let transform = canvasToScreenTransform(canvasSize: canvasSize, scale: scale, offset: offset)
        return screenPoint.applying(transform.inverted())
    }

    /// Nearest node whose hit radius (max(its own radius, minimumHitRadius)) contains the
    /// point; nil if none qualifies. Ties (exact equal distance) broken by id, ascending, so
    /// the result is deterministic rather than iteration-order-dependent.
    public static func nodeID(
        atScreenPoint screenPoint: CGPoint,
        canvasSize: CGSize,
        scale: CGFloat,
        offset: CGSize,
        positions: [String: CGPoint],
        radii: [String: CGFloat],
        minimumHitRadius: CGFloat = 8
    ) -> String? {
        let point = canvasPoint(screenPoint: screenPoint, canvasSize: canvasSize, scale: scale, offset: offset)

        var best: (id: String, distance: CGFloat)?
        for id in positions.keys.sorted() {
            guard let position = positions[id] else { continue }
            let dx = position.x - point.x
            let dy = position.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let hitRadius = max(radii[id] ?? minimumHitRadius, minimumHitRadius)
            guard distance <= hitRadius else { continue }
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }
        return best?.id
    }
}
