import Foundation

/// A raw handle identifier, normalized into a form two handles can be compared by.
/// `.other` is the deliberate fallback for anything not confidently a phone or email:
/// a non-normalized phone merely fails to merge later, one duplicate node, which PLAN.md
/// prices far cheaper than a wrong merge from guessing at a malformed identifier.
public enum NormalizedIdentifier: Sendable, Equatable {
    case email(String)
    case phone(String)
    case other(String)

    public var normalizedString: String {
        switch self {
        case .email(let value), .phone(let value), .other(let value):
            return value
        }
    }
}

public enum HandleNormalization {
    /// Characters that appear in real-world phone formatting and carry no digit information.
    private static let phonePunctuation: Set<Character> = [" ", "-", "(", ")", "."]

    public static func normalize(_ identifier: String) -> NormalizedIdentifier {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("@") {
            return .email(trimmed.lowercased())
        }
        if let phone = normalizedPhone(trimmed) {
            return .phone(phone)
        }
        // Shortcodes, alphanumeric sender ids, malformed strings: left exactly as given.
        return .other(identifier)
    }

    /// E.164-ish normalization for this dataset's US default. Anything that doesn't
    /// cleanly resolve returns nil so the caller falls back to .other.
    private static func normalizedPhone(_ input: String) -> String? {
        let stripped = String(input.filter { !phonePunctuation.contains($0) })
        guard !stripped.isEmpty else { return nil }

        if stripped.hasPrefix("+") {
            let digits = stripped.dropFirst()
            guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
            return stripped
        }

        guard stripped.allSatisfy(\.isASCIIDigit) else { return nil }

        if stripped.count == 10 {
            return "+1" + stripped
        }
        if stripped.count == 11 && stripped.hasPrefix("1") {
            return "+" + stripped
        }
        return nil
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
