import Foundation

/// The places outside the app that can ask Haven to open something.
///
/// Shared with the widget target, which is a separate process and knows
/// nothing about the app's state. The url is defined once here and read from
/// both sides, so the link a widget carries cannot drift from the link the app
/// is willing to answer.
enum HavenDeepLink: Equatable {
    /// Your own code, ready to be scanned.
    case beacon

    private static let scheme = "haven"

    var host: String {
        switch self {
        case .beacon: return "beacon"
        }
    }

    var url: URL {
        // Built from components rather than a literal so the scheme lives in
        // one place; the parts are fixed, so this cannot fail.
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = host
        guard let url = components.url else {
            preconditionFailure("HavenDeepLink built an invalid url for \(host)")
        }
        return url
    }

    /// The place this url names, or nil if Haven does not own it.
    ///
    /// A url naming somewhere unknown opens nothing rather than falling back to
    /// the nearest screen: a link that quietly lands somewhere else is worse
    /// than a link that does nothing.
    init?(url: URL) {
        // Schemes and hosts are case-insensitive by RFC 3986, and iOS hands
        // back whatever case the caller typed.
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host()?.lowercased() {
        case Self.beacon.host: self = .beacon
        default: return nil
        }
    }
}
