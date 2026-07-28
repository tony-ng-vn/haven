import SwiftUI
import WidgetKit

/// The Lock Screen widget the explainer has been promising: your code, under
/// the clock.
///
/// A shortcut, not a display. An accessory-circular widget is around 38pt
/// across, which is far below what a scannable QR needs, so drawing the real
/// code here would produce something that looks right and cannot be read. It
/// carries a mark and a deep link instead, and the scanning happens on the back
/// of the card, where the code has room to be legible.
///
/// That also means the widget needs nothing from the app: no App Group, no
/// shared container, no copy of the card kept in step across two processes.
/// The whole payload is a url that never changes.
struct BeaconWidget: Widget {
    /// Stored with the user's widget once added, so it must not change.
    private static let kind = "HavenBeacon"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BeaconProvider()) { _ in
            BeaconWidgetView()
        }
        .configurationDisplayName("Haven")
        .description("Open your code without unlocking.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// One entry, forever. Nothing the widget shows depends on the time, so asking
/// the system to refresh it would spend the app's budget to redraw the same
/// pixels.
struct BeaconProvider: TimelineProvider {
    func placeholder(in context: Context) -> BeaconEntry {
        BeaconEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (BeaconEntry) -> Void) {
        completion(BeaconEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeaconEntry>) -> Void) {
        completion(Timeline(entries: [BeaconEntry()], policy: .never))
    }
}

struct BeaconEntry: TimelineEntry {
    /// TimelineEntry requires a date. This one is only ever "now", because the
    /// entry carries nothing that ages.
    var date = Date()
}

struct BeaconWidgetView: View {
    var body: some View {
        ZStack {
            // The system's own accessory backing, which matches whatever the
            // wallpaper underneath is doing. Haven's palette is deliberately
            // absent: the Lock Screen renders accessory widgets in a single
            // system tint, so a colour here would be overridden and the code
            // would be lying about what it draws.
            AccessoryWidgetBackground()
            Image(systemName: "qrcode")
                .font(.system(size: 20, weight: .medium))
                // Marks this as the part the system tints when someone colours
                // their Lock Screen.
                .widgetAccentable()
        }
        .widgetURL(HavenDeepLink.beacon.url)
        .accessibilityLabel("Haven, open your code")
    }
}

#Preview("Beacon widget", as: .accessoryCircular) {
    BeaconWidget()
} timeline: {
    BeaconEntry()
}
