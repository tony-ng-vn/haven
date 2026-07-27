import SwiftUI
import WidgetKit

/// The widget extension's entry point.
///
/// Everything here is unconditional: `WidgetBundleBuilder` takes no `if`, so a
/// widget cannot be held back at this level. What the beacon flag governs is
/// the tap, which the app decides -- see `HavenTabs.onOpenURL`. While the flag
/// is off the widget still opens Haven, it just does not push the beacon.
///
/// One widget today. The bundle exists so adding a second (a card summary, a
/// recent-people rectangle) does not mean restructuring the target.
@main
struct HavenWidgetBundle: WidgetBundle {
    var body: some Widget {
        BeaconWidget()
    }
}
