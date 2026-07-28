import Foundation

/// What a scanned code, or a line somebody typed, points at.
///
/// A camera sees every code in front of it, most of which are not Haven's, so
/// the first job here is refusing: a Wi-Fi code, a parcel label and a rival
/// app's link all have to read as "not a Haven card" rather than as a handle
/// nobody holds.
///
/// The shape of a handle is deliberately not checked. `profiles.getByHandle`
/// validates it against `HANDLE_PATTERN` and answers null, and a second copy of
/// that rule here would be one more place to keep in step for no gain -- the
/// screen shows the same "nobody here" either way. What is checked is the part
/// the server cannot: whether this text names Haven at all.
enum ConnectAddress {
    /// The Haven handle this text names, or nil when it names something else.
    ///
    /// Three shapes, because all three arrive in practice: the full address a
    /// card's code carries, the same thing without its scheme (which is what a
    /// paste from a browser bar looks like), and a bare handle somebody read
    /// out loud.
    static func handle(in raw: String) -> String? {
        let text = raw.trimmedLikeJS
        guard !text.isEmpty, !text.contains(where: \.isJSWhitespace) else { return nil }

        // A scheme that is not the web is not a card. Haven's own `haven://`
        // urls are the widget's, and they name a screen rather than a person.
        if let scheme = scheme(of: text) {
            guard scheme == "http" || scheme == "https" else { return nil }
            return handle(inAddress: text)
        }
        // No scheme, but a host in it: still an address, and it still has to be
        // Haven's.
        if text.contains("/") || text.contains(".") {
            return handle(inAddress: "https://\(text)")
        }
        // A bare handle. Whether anybody holds it is the server's answer.
        return bare(text)
    }

    /// The site whose addresses name a Haven card.
    ///
    /// Read from `Config`, never written here, for the same reason
    /// `BeaconAddress` reads it: the code a card carries and the code this
    /// scanner accepts have to name one site, or a card made by this build
    /// would not scan into it.
    private static var host: String { Config.cardHost }

    private static func handle(inAddress text: String) -> String? {
        guard let url = URL(string: text), let found = url.host()?.lowercased() else {
            return nil
        }
        // Exact, or one label in front of it. A suffix match on a dot boundary,
        // so "inhavens.com.example.test" is a stranger's host rather than ours.
        guard found == host || found.hasSuffix(".\(host)") else { return nil }
        let segments = url.path().split(separator: "/").map(String.init)
        // One segment. The card page lives at the root of the site, so anything
        // deeper is one of the site's own pages rather than somebody's card.
        guard segments.count == 1, let segment = segments.first else { return nil }
        guard let decoded = segment.removingPercentEncoding else { return nil }
        return bare(decoded)
    }

    /// A handle with the `@` people write in front of one taken off, or nil
    /// when nothing is left.
    private static func bare(_ text: String) -> String? {
        let handle = String(text.trimmedLikeJS.drop { $0 == "@" })
        return handle.isEmpty || handle.contains("/") ? nil : handle
    }

    /// Whether the text starts with a url scheme, and which. The same rule
    /// `ProfileURL` uses, and for the same reason: a bare domain has no scheme
    /// and still names a page.
    private static func scheme(of text: String) -> String? {
        var scheme = ""
        var isFirst = true
        for character in text {
            if character == ":" { return isFirst ? nil : scheme.lowercased() }
            if isFirst {
                guard character.isASCIILetter else { return nil }
                isFirst = false
            } else {
                guard
                    character.isASCIILetter || character.isASCIIDigit
                        || character == "+" || character == "-" || character == "."
                else { return nil }
            }
            scheme.append(character)
        }
        return nil
    }
}
