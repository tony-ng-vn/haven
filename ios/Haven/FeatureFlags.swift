/// Switches for work that is finished in the app but not finished everywhere
/// else. Not a settings surface: nothing here is a person's choice.
enum FeatureFlags {
    /// The beacon screen and the shell's entry point to it.
    ///
    /// Stays false until the public web card page at `inhavens.com/<handle>`
    /// exists. The beacon's QR resolves there, and a code that lands on a 404
    /// is worse than no code at all.
    static let beaconEnabled = false
}
