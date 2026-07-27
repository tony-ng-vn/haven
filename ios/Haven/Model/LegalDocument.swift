import Foundation

/// The pages App Review expects to be able to reach from inside the app.
///
/// Guideline 5.1.1(i) asks for the privacy policy in the App Store listing and
/// in the app itself; terms rides along because the two belong together and a
/// person looking for one is usually looking for both.
///
/// The addresses are built from `Config.cardHost` rather than written out, for
/// the same reason the beacon's are: one host, decided once. A literal here
/// would be a second place to change and the first place to forget.
enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy Policy"
        case .terms: "Terms of Service"
        }
    }

    var url: URL {
        // Force-unwrapped deliberately: the host is a compile-time constant and
        // the path is this enum's own case, so a nil here is a typo in the
        // source rather than anything a running app can cause. LegalDocumentTests
        // is what actually catches it.
        URL(string: "https://\(Config.cardHost)/\(rawValue)")!
    }
}
