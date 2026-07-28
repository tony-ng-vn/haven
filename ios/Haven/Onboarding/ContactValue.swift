import Foundation
import PhoneNumberKit

/// The parsing behind the contact question, kept apart from the screen because
/// every case here is a rule about a platform, and rules are worth testing.
enum ContactValue {
    /// Reduces whatever was pasted to a bare Instagram handle.
    ///
    /// Pasting the profile link is the normal thing to do, so the handle is dug
    /// out of it rather than demanded on its own. Nil when nothing usable is
    /// left, which is what keeps Continue disabled.
    static func instagramHandle(from raw: String) -> String? {
        let handle = handle(in: raw, after: ["instagram.com/"])
        guard !handle.isEmpty, handle.count <= 30 else { return nil }
        guard handle.allSatisfy(Self.instagramCharacters.contains) else { return nil }
        return handle
    }

    /// The same for X, which still answers to both of its addresses.
    static func xHandle(from raw: String) -> String? {
        let handle = handle(in: raw, after: ["x.com/", "twitter.com/"])
        guard !handle.isEmpty, handle.count <= 15 else { return nil }
        guard handle.allSatisfy(Self.xCharacters.contains) else { return nil }
        return handle
    }

    /// The same for LinkedIn, whose profile addresses carry an `/in/` segment.
    ///
    /// Kept separate from `linkedInSlug` on purpose: this cleans up what a
    /// person supplies, while that one guesses before they have supplied
    /// anything.
    static func linkedInHandle(from raw: String) -> String? {
        let handle = handle(in: raw, after: ["linkedin.com/in/"])
        guard !handle.isEmpty, handle.count <= 100 else { return nil }
        guard handle.allSatisfy(Self.linkedInCharacters.contains) else { return nil }
        return handle
    }

    /// The same for Telegram, which serves profiles from two addresses.
    ///
    /// Never asked for on your own card -- Clerk has no Telegram connection and
    /// the card offers four platforms. It is here because a person you save by
    /// hand can carry any handle you want to record, Telegram included
    /// (`mvp-design.md`), and the rules are Telegram's own: five to
    /// thirty-two characters, letters, digits and underscores.
    static func telegramHandle(from raw: String) -> String? {
        let handle = handle(in: raw, after: ["t.me/", "telegram.me/"])
        guard handle.count >= 5, handle.count <= 32 else { return nil }
        guard handle.allSatisfy(Self.telegramCharacters.contains) else { return nil }
        return handle
    }

    /// A first guess at someone's LinkedIn address, for them to correct.
    ///
    /// LinkedIn's authorization proves who a person is and never sends their
    /// profile address, so a guess they can edit beats an empty field. Wrong is
    /// fine here; the panel exists to be corrected.
    static func linkedInSlug(from name: String) -> String {
        name
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    /// E.164, or nil when the number is not a real one.
    ///
    /// Parsed against the device's region, so someone in Vietnam can type a
    /// local number and someone in the US can type theirs, and both are stored
    /// in the one form that is unambiguous everywhere.
    static func phoneNumber(from raw: String) -> String? {
        guard let parsed = try? phoneUtility.parse(raw) else { return nil }
        return phoneUtility.format(parsed, toType: .e164)
    }

    /// As-you-type formatting for the phone field.
    static func formattingPhone(_ raw: String) -> String {
        partialFormatter.formatPartial(raw)
    }

    /// Everything up to the first separator, with any of the platform's
    /// addresses in front of it and any leading `@` removed.
    ///
    /// The hosts are tried against the whole string before anything is cut, so a
    /// platform with two addresses still finds the second one. Cutting first
    /// would leave "https:" and match neither.
    private static func handle(in raw: String, after hosts: [String]) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for host in hosts {
            guard let address = value.range(of: host, options: .caseInsensitive) else { continue }
            value = String(value[address.upperBound...])
            break
        }
        value = String(value.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private static let instagramCharacters = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"
    )
    private static let xCharacters = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    )
    private static let linkedInCharacters = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
    )
    private static let telegramCharacters = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    )

    // Both carry libphonenumber's metadata, so they are built once rather than
    // per keystroke.
    private static let phoneUtility = PhoneNumberUtility()
    private static let partialFormatter = PartialFormatter()
}
