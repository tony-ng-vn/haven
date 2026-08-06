import Foundation

/// Where a saved person's handle actually goes.
///
/// Reach is the fourth stroke of the loop -- Capture, Refine, Recall, Reach --
/// and the only one that leaves Haven. A handle Haven cannot open is still
/// worth showing: it is how you reach them, whether or not the reaching happens
/// from here.
///
/// A lookup with an honest miss rather than a switch over an enum, because a
/// saved person's platforms are free-form on purpose (`mvp-design.md`): your
/// own card offers four, and somebody you wrote down can carry any handle you
/// wanted to record.
enum PersonReach {
    /// The platforms Haven knows how to open.
    ///
    /// `twitter` is here as well as `x` because rows written before the rename
    /// still say twitter, and the person behind them has not moved.
    private enum Known: String {
        case instagram
        case x
        case twitter
        case linkedin
        case telegram
        case whatsapp
        case phone

        var label: String {
            switch self {
            case .instagram: return "Instagram"
            case .x, .twitter: return "X"
            case .linkedin: return "LinkedIn"
            case .telegram: return "Telegram"
            case .whatsapp: return "WhatsApp"
            case .phone: return "Phone"
            }
        }

        /// What sits in front of the value to make the address it points at, or
        /// nil for a platform whose value is not part of a web address.
        var addressPrefix: String? {
            switch self {
            case .instagram: return "instagram.com/"
            case .x, .twitter: return "x.com/"
            case .linkedin: return "linkedin.com/in/"
            case .telegram: return "t.me/"
            case .whatsapp, .phone: return nil
            }
        }
    }

    private static func known(_ platform: String) -> Known? {
        Known(rawValue: platform.trimmedLikeJS.lowercased())
    }

    /// Whether this platform string is LinkedIn. `PersonScreen` uses this to
    /// decide whether a handle is old enough to flag (`HandleStaleness`) --
    /// the only reason this one case needs to leave `Known`, which otherwise
    /// stays private.
    static func isLinkedIn(_ platform: String) -> Bool {
        known(platform) == .linkedin
    }

    /// The platforms the handle editor offers.
    ///
    /// Longer than the four your own card offers, and that asymmetry is the
    /// spec's: your card is an identity you publish, this is a note about how
    /// you actually reach one person, "WhatsApp and Telegram included"
    /// (`mvp-design.md`). `twitter` is readable but not offerable -- it is the
    /// old name for a platform that has one.
    ///
    /// Offering a list rather than a free text box is a decision about dedup,
    /// not about capability: the server takes any string, and one person typing
    /// "WhatsApp" while another types "whats app" makes two identities for one
    /// platform, invisibly.
    static let offerable = ["instagram", "x", "linkedin", "phone", "whatsapp", "telegram"]

    /// The value as it will be stored, or nil while there is not a usable one.
    ///
    /// Every rule here already existed for the contact question, because a
    /// handle is a fact about a platform rather than about the screen that
    /// asked for it. A platform Haven does not know keeps whatever was typed,
    /// trimmed: refusing it would be claiming a rule Haven does not have.
    static func parse(platform: String, from raw: String) -> String? {
        guard let known = known(platform) else {
            let trimmed = raw.trimmedLikeJS
            return trimmed.isEmpty ? nil : trimmed
        }
        switch known {
        case .instagram: return ContactValue.instagramHandle(from: raw)
        case .x, .twitter: return ContactValue.xHandle(from: raw)
        case .linkedin: return ContactValue.linkedInHandle(from: raw)
        case .phone, .whatsapp: return ContactValue.phoneNumber(from: raw)
        case .telegram: return ContactValue.telegramHandle(from: raw)
        }
    }

    /// Whether this handle is a phone number, which decides the keyboard and
    /// the autofill hint the field asks for.
    static func isPhoneNumber(_ platform: String) -> Bool {
        let known = known(platform)
        return known == .phone || known == .whatsapp
    }

    static func placeholder(_ platform: String) -> String {
        isPhoneNumber(platform) ? "Their number" : "Paste a link or type the handle"
    }

    /// What to open when somebody taps this handle, or nil when there is
    /// nothing to open.
    ///
    /// Nil is an ordinary answer. A handle on a platform Haven has never heard
    /// of is a real way to reach somebody and the row still shows it; it just
    /// does not promise a tap it cannot keep.
    ///
    /// `platformId` only changes anything for X: a link built from it survives
    /// a handle rename, which one built from the handle alone does not -- this
    /// is the address format X's own developer docs recommend for exactly that
    /// reason. Instagram's app-vs-web choice for a resolved id lives one level
    /// up, in `openURL` below, because it depends on `canOpenURL`, which only
    /// UIKit can answer; the web fallback here is unchanged either way.
    static func url(platform: String, value: String, platformId: String? = nil) -> URL? {
        let value = value.trimmedLikeJS
        guard !value.isEmpty, let known = known(platform) else { return nil }
        switch known {
        case .phone:
            // A number is dialled, not browsed. Everything but the digits and a
            // leading plus goes: a stored "+84 90 123 4567" is one number, and
            // tel: does not want its spaces.
            let dialable = dialable(value)
            guard !dialable.isEmpty else { return nil }
            return URL(string: "tel:\(dialable)")
        case .whatsapp:
            // wa.me addresses a number without its plus.
            let digits = value.filter(\.isASCIIDigit)
            guard !digits.isEmpty else { return nil }
            return URL(string: "https://wa.me/\(digits)")
        case .x, .twitter:
            if let platformId, !platformId.trimmedLikeJS.isEmpty {
                return URL(string: "https://x.com/intent/user?user_id=\(platformId.trimmedLikeJS)")
            }
            guard let prefix = known.addressPrefix,
                let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            else { return nil }
            return URL(string: "https://\(prefix)\(escaped)")
        case .instagram, .linkedin, .telegram:
            guard let prefix = known.addressPrefix else { return nil }
            guard let escaped = value.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) else { return nil }
            return URL(string: "https://\(prefix)\(escaped)")
        }
    }

    /// Instagram's own app deep link for a resolved numeric id, or nil
    /// without one. Reachable only when the app is installed, which
    /// `openURL` below checks via `canOpenURL` -- `LSApplicationQueriesSchemes`
    /// in Info.plist is what lets that answer honestly rather than always
    /// saying no.
    static func instagramAppURL(platformId: String) -> URL? {
        let trimmed = platformId.trimmedLikeJS
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "instagram://user?id=\(trimmed)")
    }

    /// Which URL a tap on this handle should actually open: Instagram's app
    /// deep link when there is a resolved id and the app can open it, `url`'s
    /// answer otherwise.
    ///
    /// `canOpenAppURL` is a parameter rather than this function calling
    /// `UIApplication` itself, so the decision -- app link chosen only when
    /// both a platformId exists and the app answers yes -- is what a test
    /// pins, not whether Instagram happens to be installed on whatever ran it.
    static func openURL(
        platform: String,
        value: String,
        platformId: String? = nil,
        canOpenAppURL: (URL) -> Bool
    ) -> URL? {
        if known(platform) == .instagram, let platformId,
            let appURL = instagramAppURL(platformId: platformId), canOpenAppURL(appURL)
        {
            return appURL
        }
        return url(platform: platform, value: value, platformId: platformId)
    }

    /// How the handle reads on screen: the address it points at, or the value
    /// itself.
    ///
    /// The same shape the card uses, and for the same reason -- Haven draws no
    /// brand glyphs, so an address is what says which platform this is. A
    /// platform with no address shows the value, which for a number is the only
    /// honest thing to show anyway.
    static func display(platform: String, value: String) -> String {
        guard let prefix = known(platform)?.addressPrefix else { return value }
        return prefix + value
    }

    /// What the platform is called out loud.
    ///
    /// An unknown platform is read back as it was written rather than dressed
    /// up: somebody who typed "signal" gets "signal", which is true, and Haven
    /// does not pretend to know a platform it does not.
    static func label(_ platform: String) -> String {
        known(platform)?.label ?? platform
    }

    /// The digits of a number, keeping a leading plus.
    private static func dialable(_ value: String) -> String {
        let digits = value.filter(\.isASCIIDigit)
        guard !digits.isEmpty else { return "" }
        return value.hasPrefix("+") ? "+\(digits)" : digits
    }
}
