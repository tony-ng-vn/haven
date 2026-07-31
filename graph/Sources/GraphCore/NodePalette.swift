import Foundation

/// Plain RGBA components (0...1), framework-agnostic: both the SwiftUI screen renderer
/// (via App/Sources/NodeColor.swift, which wraps these in a SwiftUI Color) and the headless
/// GraphImageRenderer draw from this one table, so they can never drift apart from each other.
public struct RGBAColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public enum NodePalette {
    public static func color(for kind: NodeKind) -> RGBAColor {
        switch kind {
        case .user:
            return RGBAColor(red: 0.95, green: 0.82, blue: 0.35) // gold: the one node that is never anyone else
        case .person:
            return RGBAColor(red: 0.40, green: 0.70, blue: 1.0) // cool blue
        case .group:
            return RGBAColor(red: 1.0, green: 0.55, blue: 0.35) // warm orange
        }
    }

    public static let background = RGBAColor(red: 0, green: 0, blue: 0)
    public static let edge = RGBAColor(red: 1, green: 1, blue: 1)
    public static let label = RGBAColor(red: 1, green: 1, blue: 1)
}
