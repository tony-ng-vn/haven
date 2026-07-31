import SwiftUI
import GraphCore

/// Wraps NodePalette's plain RGBA components in a SwiftUI Color: the actual numbers live in
/// GraphCore now (NodePalette), shared with the headless GraphImageRenderer, so screen and
/// export can never drift apart from each other. This file, and the extension below, are the
/// only place that touches SwiftUI's Color type for a palette value -- not worth a test of
/// its own, same as before this refactor.
enum NodeColor {
    static func color(for kind: NodeKind) -> Color {
        Color(NodePalette.color(for: kind))
    }
}

extension Color {
    init(_ palette: RGBAColor) {
        self.init(red: palette.red, green: palette.green, blue: palette.blue, opacity: palette.alpha)
    }
}
