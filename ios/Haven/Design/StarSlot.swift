import Foundation

/// Which star of the figure each profile field owns.
///
/// Fixed once, deliberately not dynamic. The prototype lights stars by count,
/// which means a star changes meaning as fields come and go; the edit screen's
/// unlit stars are only legible if a field's star never moves.
enum StarSlot: Int, CaseIterable {
    case name = 0
    case city = 1
    case primaryContact = 2
    case photo = 3
    case company = 4
    case role = 5
}

extension StarSlot {
    /// The indices into `Sky.majors` that should render lit.
    ///
    /// The generator produces 7 or 8 majors but there are only 6 fields, so the
    /// last one or two majors are ambient figure stars. They read as always lit:
    /// an ambient star has no field behind it, so dimming it would be a nudge
    /// pointing at nothing, and the person could never switch it on.
    static func litMajorIndices(filled: Set<StarSlot>, majorCount: Int) -> Set<Int> {
        guard majorCount > 0 else { return [] }
        var lit: Set<Int> = []
        for index in 0..<majorCount {
            if let slot = StarSlot(rawValue: index) {
                if filled.contains(slot) { lit.insert(index) }
            } else {
                lit.insert(index)
            }
        }
        return lit
    }
}
