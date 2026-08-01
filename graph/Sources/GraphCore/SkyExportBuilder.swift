import Foundation

/// Fills viewer/template-v4.html's two placeholders in-process, the app's own equivalent of
/// viewer/build.py -- a downloaded build ships with no Python and no repo checkout, so this
/// cannot shell out to the script; it has to do the same substitution natively.
public enum SkyExportBuilder {
    public enum BuildError: Error, Equatable, Sendable {
        /// A required placeholder is missing from the template entirely -- shipping it
        /// unsubstituted would be a JS syntax error and a blank canvas with no error
        /// surfaced anywhere, so this fails loudly instead.
        case placeholderMissing(String)
        /// A required placeholder appears more than once. replacingOccurrences (like
        /// build.py's str.replace) replaces EVERY occurrence, so a stray second mention (the
        /// placeholder name written out in a doc comment, say) would silently splice the
        /// payload into the comment too -- fail loudly instead of shipping a corrupted file.
        case placeholderAppearsMultipleTimes(String, count: Int)
    }

    private static let corePlaceholder = "__VIEWER_CORE_JS__"
    private static let jsonPlaceholder = "__GRAPH_JSON__"

    /// Mirrors viewer/build.py's strip_exports() EXACTLY -- see that file's own header
    /// comment, which states the pattern verbatim as the canonical source of truth. Kept
    /// textually identical to that Python raw string (`\\b` here is Swift's escaping of the
    /// same literal `\b` token) so the two can be diffed by eye and never silently drift
    /// apart; cross-checked at the time this landed by running both implementations against
    /// the real viewer_core.mjs and confirming byte-identical output.
    ///
    /// A function, not a stored `static let`: `Regex` is not `Sendable`, and Swift 6's
    /// strict concurrency checking rejects a non-Sendable type held in mutable global state --
    /// recompiling this tiny pattern on each call is free next to writing an HTML file.
    private static func exportStripRegex() -> Regex<AnyRegexOutput> {
        try! Regex("(?m)^export (function|const)\\b") // pattern is a static, known-valid literal
    }

    /// Mirrors build.py's rules exactly: both placeholders must appear EXACTLY once each
    /// (never zero, never more -- see BuildError's own doc comments for why), viewer_core.mjs
    /// is spliced in with only the `export ` keyword stripped from its top-level
    /// declarations (nothing else about the file's text changes), and the JSON is embedded
    /// as-is (GraphJSON.encode already produces ASCII-safe, non-pretty-printed output) with
    /// every `</` escaped to `<\/` so a person or group name containing `</script>` cannot
    /// close the tag it is embedded inside.
    public static func build(template: String, viewerCoreSource: String, graphJSON: Data) throws -> String {
        // Checked before any substitution happens, core placeholder first: matches build.py's
        // own loop order and its "fail before writing anything" posture exactly.
        try assertAppearsExactlyOnce(corePlaceholder, in: template)
        try assertAppearsExactlyOnce(jsonPlaceholder, in: template)

        let strippedCore = viewerCoreSource.replacing(exportStripRegex()) { match in
            match.output[1].substring ?? ""
        }
        var payload = String(decoding: graphJSON, as: UTF8.self)
        payload = payload.replacingOccurrences(of: "</", with: "<\\/")

        return template
            .replacingOccurrences(of: corePlaceholder, with: strippedCore)
            .replacingOccurrences(of: jsonPlaceholder, with: payload)
    }

    /// components(separatedBy:).count - 1 counts non-overlapping occurrences, the same thing
    /// build.py's str.count(placeholder) counts.
    private static func assertAppearsExactlyOnce(_ placeholder: String, in template: String) throws {
        let count = template.components(separatedBy: placeholder).count - 1
        if count == 0 {
            throw BuildError.placeholderMissing(placeholder)
        }
        if count > 1 {
            throw BuildError.placeholderAppearsMultipleTimes(placeholder, count: count)
        }
    }
}
