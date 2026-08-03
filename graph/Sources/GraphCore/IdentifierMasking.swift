import Foundation

/// One masking rule, shared by every surface that shows a fragment of a real identifier
/// instead of the whole thing: killlist (an on-screen review tool) and GraphJSON's name
/// disambiguator (an export field a user-facing search box renders). Kept in one place so the
/// two can never quietly drift into showing a different amount of the same identifier.
public enum IdentifierMasking {
    public static let visibleSuffixLength = 4

    /// killlist's original masking shape, moved here unchanged: all but the last 4 characters
    /// replaced with 'x', preserving the original length. Returns the identifier unchanged when
    /// it is already at or under the visible length -- fine for killlist's own on-screen,
    /// never-shared use; `shortSuffix` below is stricter for a surface that ships in an export.
    public static func mask(_ identifier: String) -> String {
        guard identifier.count > visibleSuffixLength else { return identifier }
        let maskedCount = identifier.count - visibleSuffixLength
        return String(repeating: "x", count: maskedCount) + identifier.suffix(visibleSuffixLength)
    }

    /// A compact "...1234" form sized for a small inline badge (the name disambiguator) --
    /// same "only the last 4 characters are ever visible" rule as `mask`, a different, more
    /// compact shape.
    ///
    /// For an email-shaped identifier (contains "@"), the last 4 characters come from the
    /// LOCAL PART (before "@"), never the whole address: two different people who both use
    /// Gmail would otherwise both end in "...com", and a disambiguator that cannot actually
    /// tell them apart is worse than none. A phone number or any other identifier with no "@"
    /// uses its own last 4 characters directly.
    ///
    /// Never leaks a full identifier even in the short case: an identifier (or local part) at
    /// or under the visible length is masked entirely to "..." rather than shown raw, which
    /// `mask` above does NOT guarantee (its own guard returns a short identifier verbatim --
    /// acceptable for killlist's on-screen-only use, not acceptable for an export field).
    public static func shortSuffix(_ identifier: String) -> String {
        let source = localPart(of: identifier)
        guard source.count > visibleSuffixLength else { return "..." }
        return "..." + source.suffix(visibleSuffixLength)
    }

    private static func localPart(of identifier: String) -> String {
        guard let atIndex = identifier.firstIndex(of: "@") else { return identifier }
        return String(identifier[identifier.startIndex..<atIndex])
    }
}
