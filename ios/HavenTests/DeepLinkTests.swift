import Foundation
import Testing

@testable import Haven

@Suite("Deep links")
struct DeepLinkTests {
    /// The Lock Screen widget cannot reach the app's state, so all it carries
    /// is this url. Both sides read it from `HavenDeepLink`, so the widget
    /// cannot drift from what the app is willing to open.
    @Test("the beacon url the widget carries is the one the app answers")
    func beaconRoundTrips() {
        #expect(HavenDeepLink(url: HavenDeepLink.beacon.url) == .beacon)
    }

    @Test("the beacon url reads as written")
    func beaconUrlIsStable() {
        #expect(HavenDeepLink.beacon.url.absoluteString == "haven://beacon")
    }

    /// A url Haven does not own must not open anything. A widget or a pasted
    /// link naming an unknown place is a no-op, not a guess at the nearest
    /// screen.
    @Test("a url Haven does not recognise opens nothing")
    func unknownUrlsAreRejected() {
        #expect(HavenDeepLink(url: URL(string: "haven://nowhere")!) == nil)
        #expect(HavenDeepLink(url: URL(string: "https://inhavens.com/beacon")!) == nil)
        #expect(HavenDeepLink(url: URL(string: "otherapp://beacon")!) == nil)
    }

    /// iOS hands back whatever case the caller typed, and a scheme is
    /// case-insensitive by RFC. Matching exactly would drop a link that is
    /// perfectly valid.
    @Test("the scheme and host match regardless of case")
    func matchingIsCaseInsensitive() {
        #expect(HavenDeepLink(url: URL(string: "HAVEN://BEACON")!) == .beacon)
    }

    /// The widget is a second door into the beacon that the toolbar's own check
    /// does not cover. Written against the flag rather than against `false` so
    /// it keeps asserting the coupling after the flag flips, instead of just
    /// becoming a failing test somebody deletes.
    @Test("the widget's url opens the beacon exactly when the flag allows it")
    func widgetUrlFollowsTheFlag() {
        #expect(HavenTabs.opensBeacon(HavenDeepLink.beacon.url) == FeatureFlags.beaconEnabled)
    }

    @Test("a url Haven does not own is refused whatever the flag says")
    func unknownUrlsNeverOpenTheBeacon() {
        #expect(HavenTabs.opensBeacon(URL(string: "haven://nowhere")!) == false)
        #expect(HavenTabs.opensBeacon(URL(string: "https://inhavens.com/beacon")!) == false)
    }
}
