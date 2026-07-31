import SwiftUI
import GraphCore

/// Trivial, static, and SwiftUI-Color-specific (unlike LabelBudget/EdgeRenderList, which are
/// pure enough to live in GraphCore and be unit tested there): a lookup table like this one
/// is not worth a test of its own.
enum NodeColor {
    static func color(for kind: NodeKind) -> Color {
        switch kind {
        case .user:
            return Color(red: 0.95, green: 0.82, blue: 0.35) // gold: the one node that is never anyone else
        case .person:
            return Color(red: 0.40, green: 0.70, blue: 1.0) // cool blue
        case .group:
            return Color(red: 1.0, green: 0.55, blue: 0.35) // warm orange
        }
    }
}
