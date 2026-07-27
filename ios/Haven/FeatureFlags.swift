/// Switches for work that is finished in the app but not finished everywhere
/// else. Not a settings surface: nothing here is a person's choice.
enum FeatureFlags {
    /// The beacon screen, the People toolbar's way into it, and the Lock Screen
    /// widget that opens it.
    ///
    /// Follows the build rather than being set by hand, because the thing that
    /// decides it is `Config.convexDeploymentUrl` and the two must not be able
    /// to disagree. A beacon is only worth showing when the app and the card
    /// page read the same database:
    ///
    /// - debug writes to the dev deployment, which nothing on the web reads, so
    ///   a code made there resolves to nobody. Off.
    /// - release writes to the deployment inhavens.com reads, so a scan lands
    ///   on the right card. On.
    ///
    /// The page itself now exists, which is what changed here. It was false
    /// everywhere while `inhavens.com/<handle>` was a 404.
    ///
    /// `BeaconTests` asserts this against the deployment, so moving one without
    /// the other fails rather than shipping a code that goes nowhere.
    #if DEBUG
    static let beaconEnabled = false
    #else
    static let beaconEnabled = true
    #endif
}
