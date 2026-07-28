import SwiftUI
import WidgetKit

/// The widget extension's entry point.
///
/// One widget today. The bundle exists so adding a second (a card summary, a
/// recent-people rectangle) does not mean restructuring the target.
@main
struct HavenWidgetBundle: WidgetBundle {
    var body: some Widget {
        BeaconWidget()
    }
}
