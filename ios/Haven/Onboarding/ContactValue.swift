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
        let handle = handle(in: raw, after: "instagram.com/")
        guard !handle.isEmpty, handle.count <= 30 else { return nil }
        guard handle.allSatisfy(Self.instagramCharacters.contains) else { return nil }
        return handle
    }

    /// The same for LinkedIn, whose profile addresses carry an `/in/` segment.
    ///
    /// Kept separate from `linkedInSlug` on purpose: this cleans up what a
    /// person supplies, while that one guesses before they have supplied
    /// anything.
    static func linkedInHandle(from raw: String) -> String? {
        let handle = handle(in: raw, after: "linkedin.com/in/")
        guard !handle.isEmpty, handle.count <= 100 else { return nil }
        guard handle.allSatisfy(Self.linkedInCharacters.contains) else { return nil }
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

    /// Everything up to the first separator, with any address in front of it and
    /// any leading `@` removed.
    private static func handle(in raw: String, after host: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address = value.range(of: host, options: .caseInsensitive) {
            value = String(value[address.upperBound...])
        }
        value = String(value.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private static let instagramCharacters = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"
    )
    private static let linkedInCharacters = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
    )

    // Both carry libphonenumber's metadata, so they are built once rather than
    // per keystroke.
    private static let phoneUtility = PhoneNumberUtility()
    private static let partialFormatter = PartialFormatter()
}
