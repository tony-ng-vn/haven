import Foundation

/// A platform whose profile URLs Haven can turn into a person.
///
/// Only the three the share extension activates on. The raw values are the
/// strings `saveSharedProfile` expects, so a parse result travels to Convex
/// without a translation step in between.
enum SharedPlatform: String, Codable, Sendable, CaseIterable {
    case instagram
    case linkedin
    case x
}

/// One person's account on one platform: the identity a share resolves to.
///
/// This pair is the dedup key `saveSharedProfile` writes on, which is why
/// `ProfileURL` is pinned against vectors generated from the TypeScript rather
/// than tested on its own terms. See `HavenTests/SharedFixtures.swift`.
struct ProfileLink: Equatable, Codable, Sendable {
    let platform: SharedPlatform
    let handle: String
}

/// Turns a shared URL into the person it points at.
///
/// A port of `parseProfileUrl`, `normalizeUrl` and `nameGuessFromSlug` in
/// `src/lib.ts`. Pure and offline by design: the URL is a pointer, never
/// fetched, and the extension does no network at all.
///
/// Foundation only, on purpose. This file is compiled into the share
/// extension, which is a separate process on a tight memory budget and must
/// not pull in Clerk or Convex.
enum ProfileURL {
    // MARK: - Normalizing

    /// An openable http(s) URL, or nil when the text is not a link at all.
    ///
    /// Bare domains are upgraded because X shares a URL with no scheme, and
    /// rejecting those would reject the platform people share from most.
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmedLikeJS
        if trimmed.isEmpty || trimmed.contains(where: \.isJSWhitespace) {
            return nil
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return trimmed
        }
        // Any other explicit scheme (ftp:, mailto:, javascript:) is not
        // openable from here; only bare domains get upgraded.
        if hasScheme(trimmed) {
            return nil
        }
        if !trimmed.contains(".") {
            return nil
        }
        return "https://\(trimmed)"
    }

    /// Whether the text starts with a URL scheme: a letter, then any of
    /// letters, digits, `+`, `-` and `.`, then a colon.
    private static func hasScheme(_ text: String) -> Bool {
        var isFirst = true
        for character in text {
            if character == ":" { return !isFirst }
            if isFirst {
                guard character.isASCIILetter else { return false }
                isFirst = false
                continue
            }
            guard
                character.isASCIILetter || character.isASCIIDigit
                    || character == "+" || character == "-" || character == "."
            else { return false }
        }
        return false
    }

    // MARK: - Parsing

    /// First path segments that are product surfaces, not people. A share of a
    /// reel or a login page must never become a person.
    private static let reservedPaths: [SharedPlatform: Set<String>] = [
        .instagram: [
            "p", "reel", "reels", "stories", "tv", "explore", "accounts",
            "direct", "about",
        ],
        // LinkedIn needs no list: the /in/ prefix below already excludes every
        // other surface.
        .linkedin: [],
        .x: [
            "home", "explore", "search", "i", "intent", "hashtag", "messages",
            "notifications", "settings", "compose", "share",
        ],
    ]

    /// A specific post under a handle is content someone shared, not the
    /// profile; deeper profile tabs (/tagged, /in/<slug>/details) still
    /// identify the person.
    private static let contentSubpaths: [SharedPlatform: Set<String>] = [
        .instagram: ["p", "reel", "tv"],
        .linkedin: [],
        .x: ["status"],
    ]

    /// The registrable domains that serve profiles, not exact hosts: share
    /// sheets hand over whichever host the app is on, and LinkedIn gives
    /// non-US members a country-prefixed one (vn.linkedin.com) alongside the
    /// www./m./mobile. variants.
    private static let profileHosts: [(domain: String, platform: SharedPlatform)] = [
        ("instagram.com", .instagram),
        ("linkedin.com", .linkedin),
        ("x.com", .x),
        ("twitter.com", .x),
    ]

    /// The person a shared URL points at, or nil for anything that is not one
    /// person's profile.
    static func parse(_ raw: String) -> ProfileLink? {
        guard let normalized = normalize(raw) else { return nil }
        let (host, path) = hostAndPath(of: normalized)
        guard let platform = platformForHost(host) else { return nil }

        // The path exactly as written, decoded one segment at a time below. A
        // path decoded whole would let an encoded slash become a real
        // separator, and "%73tatus" would smuggle a post past the checks.
        var segments = removeDotSegments(path.split(separator: "/").map(String.init))

        if platform == .linkedin {
            // The mobile-lite site serves the same profile one segment deeper.
            if segments.first == "mwlite" {
                segments.removeFirst()
            }
            // Profiles live only under /in/<slug>; company, posts, pub and
            // feed paths are not a person we can identify.
            guard segments.first == "in" else { return nil }
            segments.removeFirst()
        }

        guard let handleSegment = segments.first else { return nil }
        if segments.count > 1 {
            // Decoded first, so "%73tatus" cannot smuggle a post past the
            // check.
            let sub = decodeComponent(segments[1]) ?? segments[1]
            if contentSubpaths[platform, default: []].contains(sub.lowercased()) {
                return nil
            }
        }

        // A malformed escape is a broken link, not a person.
        guard let decoded = decodeComponent(handleSegment) else { return nil }
        // An encoded slash would otherwise fold a second path segment into the
        // handle, hiding the surface this URL actually points at.
        if decoded.contains("/") { return nil }
        let handle = String(decoded.drop { $0 == "@" })
        if handle.isEmpty { return nil }
        // Checked after decoding: "%70" is the reserved "p", and a post URL
        // must never become a person.
        if reservedPaths[platform, default: []].contains(handle.lowercased()) {
            return nil
        }
        return ProfileLink(platform: platform, handle: handle)
    }

    /// The platform a host serves profiles for.
    ///
    /// Lowercased here rather than trusted to Foundation, which leaves host
    /// case alone where the JS URL parser normalizes it -- a share from an app
    /// that capitalized anything would otherwise match no platform at all.
    private static func platformForHost(_ rawHost: String) -> SharedPlatform? {
        let host = rawHost.lowercased()
        for (domain, platform) in profileHosts {
            // A suffix match on a dot boundary, so "instagram.com.evil.example"
            // is still a stranger's host.
            if host == domain || host.hasSuffix(".\(domain)") {
                return platform
            }
        }
        return nil
    }

    /// The host and the path of a normalized URL, exactly as they were
    /// written.
    ///
    /// Hand-rolled rather than `URLComponents`, which rewrites a stray `%`
    /// into `%25`. That turns a malformed escape -- a broken link the server
    /// refuses -- into a handle that decodes cleanly and names nobody.
    private static func hostAndPath(of normalized: String) -> (host: String, path: String) {
        var rest = Substring(normalized)
        if let scheme = rest.range(of: "://") {
            rest = rest[scheme.upperBound...]
        }
        let authorityEnd =
            rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" } ?? rest.endIndex
        var authority = rest[..<authorityEnd]
        let path = rest[authorityEnd...].prefix { $0 != "?" && $0 != "#" }
        // Credentials in front of the host are not part of it, and the last
        // "@" wins so a password holding one cannot move the boundary.
        if let credentials = authority.lastIndex(of: "@") {
            authority = authority[authority.index(after: credentials)...]
        }
        // Nor is a port. An IPv6 literal keeps its colons inside brackets, and
        // never names a profile host anyway.
        if !authority.hasPrefix("["), let port = authority.lastIndex(of: ":") {
            authority = authority[..<port]
        }
        return (String(authority), String(path))
    }

    /// `decodeURIComponent`, including the part that matters: it refuses.
    ///
    /// Foundation's `removingPercentEncoding` is lenient where the server's
    /// decoder throws, and this is the only place the difference is load
    /// bearing -- a half-written escape is a broken link, and the server
    /// answers null for it.
    private static func decodeComponent(_ segment: String) -> String? {
        let source = Array(segment.utf8)
        var bytes: [UInt8] = []
        var index = 0
        while index < source.count {
            guard source[index] == UInt8(ascii: "%") else {
                bytes.append(source[index])
                index += 1
                continue
            }
            guard
                index + 2 < source.count,
                let high = hexDigit(source[index + 1]),
                let low = hexDigit(source[index + 2])
            else { return nil }
            bytes.append(high << 4 | low)
            index += 3
        }
        // Valid escapes can still spell a byte sequence that is not text.
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    /// Collapses `.` and `..` the way a URL parser does before anyone reads
    /// the path.
    ///
    /// The server parses with `new URL`, which has already done this by the
    /// time it splits the path, so skipping it here would read a different
    /// segment as the handle for the same URL. A percent-encoded dot segment
    /// still counts as one, which is why this runs before the segments are
    /// decoded.
    private static func removeDotSegments(_ segments: [String]) -> [String] {
        var out: [String] = []
        for segment in segments {
            let dots = segment.replacingOccurrences(
                of: "%2e",
                with: ".",
                options: [.caseInsensitive]
            )
            switch dots {
            case ".":
                continue
            case "..":
                if !out.isEmpty { out.removeLast() }
            default:
                out.append(segment)
            }
        }
        return out
    }

    // MARK: - Name guessing

    /// The name a LinkedIn slug carries ("mai-tran-8a91b2" -> "Mai Tran"), or
    /// "" when there is nothing to guess.
    ///
    /// This makes the share sheet's name field a confirmation rather than an
    /// empty box. Only LinkedIn slugs carry a name; Instagram and X hand over
    /// a handle, and a capitalized handle looks like a name without being one.
    static func nameGuess(fromSlug slug: String) -> String {
        var segments = slug.trimmedLikeJS.split(separator: "-").map(String.init)
        // Only the trailing id junk is dropped: digits earlier in a slug are
        // part of the handle someone actually chose.
        while let last = segments.last, last.contains(where: \.isASCIIDigit) {
            segments.removeLast()
        }
        return segments.map(capitalizingFirst).joined(separator: " ")
    }

    /// Upper-cases the first character and leaves the rest exactly as typed,
    /// matching the server's `charAt(0).toUpperCase() + slice(1)`. Deliberately
    /// not `capitalized`, which also lower-cases the rest and would turn
    /// "MaiMakes" into "Maimakes".
    private static func capitalizingFirst(_ part: String) -> String {
        guard let first = part.first else { return part }
        return first.uppercased() + part.dropFirst()
    }
}

// MARK: - The character classes the server's regexes use

extension Character {
    /// `[a-zA-Z]`, not Unicode's idea of a letter.
    var isASCIILetter: Bool {
        ("a"..."z").contains(self) || ("A"..."Z").contains(self)
    }

    /// `\d` as JavaScript means it: `[0-9]`, not every Unicode decimal digit.
    /// `CharacterSet.decimalDigits` would drop a slug segment the server keeps.
    var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }

    /// `\s` as JavaScript means it, which is a fixed list rather than Unicode's
    /// White_Space property. Two characters sit on the seam: a byte-order mark
    /// is whitespace to a JS regex and not to Unicode, and NEL (U+0085) is the
    /// other way round. Following Unicode would fold names the server does not.
    var isJSWhitespace: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else {
            return false
        }
        switch scalar.value {
        case 0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029,
            0x202f, 0x205f, 0x3000, 0xfeff:
            return true
        default:
            return false
        }
    }
}

extension String {
    /// `String.prototype.trim()`, which strips exactly the characters a JS
    /// regex calls `\s` -- not the same set as `.whitespacesAndNewlines`.
    var trimmedLikeJS: String {
        String(drop(while: \.isJSWhitespace).reversed()
            .drop(while: \.isJSWhitespace).reversed())
    }
}
