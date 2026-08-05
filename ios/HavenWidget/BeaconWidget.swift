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
/// Accessory-rectangular is the other Lock Screen slot people actually reach
/// for -- the wider one that sits below the clock -- and it is wide enough for
/// the mark and "Haven" and a line of copy, so it is declared too. Nothing
/// wider (a Home Screen family, say) is: those get real room to draw the card
/// itself, which is a different feature this widget does not try to become.
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
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
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

/// One entry, two renderings. Nothing here depends on app state -- see the
/// widget's own doc comment -- so there is no signed-out or no-data branch to
/// draw: every family always shows the same mark and the same deep link, which
/// is itself the deliberate empty-ish state rather than a placeholder standing
/// in for one.
struct BeaconWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(HavenDeepLink.beacon.url)
            .accessibilityLabel("Haven, open your code")
            // Required since iOS 17, for every family, including the accessory
            // ones that mostly ignore it: a widget that never declares its own
            // background this way is one WidgetKit refuses to render at all,
            // showing its own "Please adopt containerBackground" placeholder
            // in the gallery and, live, on the Lock Screen -- a grey circle,
            // an exclamation badge, truncated system copy, no Haven mark
            // anywhere in it. That placeholder is what the owner saw on
            // device; this is the fix, not a cosmetic pass. The background
            // itself is the same system accessory backing every family here
            // already wanted, just declared through the API that now gates
            // whether anything renders at all rather than layered by hand.
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        default:
            circular
        }
    }

    private var circular: some View {
        Image(systemName: "qrcode")
            .font(.system(size: 20, weight: .medium))
            // Marks this as the part the system tints when someone colours
            // their Lock Screen.
            .widgetAccentable()
    }

    /// Wide enough for the name, unlike the circle -- so this is the one
    /// rendering that actually says "Haven" rather than trusting the gallery
    /// listing and the glyph to carry that alone.
    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.system(size: 18, weight: .medium))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text("Haven")
                    .font(.headline)
                Text("Open your code")
                    .font(.caption2)
            }
        }
    }
}

#Preview("Beacon widget, circular", as: .accessoryCircular) {
    BeaconWidget()
} timeline: {
    BeaconEntry()
}

#Preview("Beacon widget, rectangular", as: .accessoryRectangular) {
    BeaconWidget()
} timeline: {
    BeaconEntry()
}
