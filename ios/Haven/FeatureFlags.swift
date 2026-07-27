/// Switches for work that is finished in the app but not finished everywhere
/// else. Not a settings surface: nothing here is a person's choice.
///
/// Compiled into the widget target too, so one switch governs every way into a
/// feature rather than the app and the Lock Screen disagreeing about it.
enum FeatureFlags {
    /// The beacon screen, the shell's entry point to it, and the Lock Screen
    /// widget that opens it.
    ///
    /// Stays false until the public web card page at `inhavens.com/<handle>`
    /// exists. The beacon's QR resolves there, and a code that lands on a 404
    /// is worse than no code at all.
    ///
    /// Flip it locally to work on any of the three. `BeaconTests` asserts it is
    /// false so that a local flip cannot travel to main by accident.
    static let beaconEnabled = false
}
