import Foundation

/// Fills a sky template's placeholder(s) in-process, the app's own equivalent of
/// viewer/build.py -- a downloaded build ships with no Python and no repo checkout, so this
/// cannot shell out to the script; it has to do the same substitution natively.
/// __GRAPH_JSON__ is always required, exactly once. __VIEWER_CORE_JS__ is CONDITIONAL: some
/// templates (template-v4.html, the map presentation) declare it because their viewer logic
/// lives in a separate viewer_core.mjs; others (template-sky.html, the two-plane ringed sky)
/// have their logic inline already and never mention it at all. build.py is gaining this same
/// conditional in parallel -- see that file's own header comment for the shared source of truth.
public enum SkyExportBuilder {
    public enum BuildError: Error, Equatable, Sendable {
        /// A required placeholder is missing from the template entirely -- shipping it
        /// unsubstituted would be a JS syntax error and a blank canvas with no error
        /// surfaced anywhere, so this fails loudly instead. __GRAPH_JSON__ only: a template
        /// with no __VIEWER_CORE_JS__ at all is a valid shape (see viewerCoreSourceRequired
        /// for the case that IS an error).
        case placeholderMissing(String)
        /// A required placeholder appears more than once. replacingOccurrences (like
        /// build.py's str.replace) replaces EVERY occurrence, so a stray second mention (the
        /// placeholder name written out in a doc comment, say) would silently splice the
        /// payload into the comment too -- fail loudly instead of shipping a corrupted file.
        case placeholderAppearsMultipleTimes(String, count: Int)
        /// The template declares __VIEWER_CORE_JS__ exactly once -- it wants core JS spliced
        /// in -- but the caller passed no source to splice. Distinct from placeholderMissing,
        /// which is about the PLACEHOLDER text; this is about the VALUE meant to fill it.
        case viewerCoreSourceRequired
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

    /// __GRAPH_JSON__ is unconditionally required, exactly once, in every template shape.
    /// __VIEWER_CORE_JS__ is conditional on the template: zero occurrences skips core
    /// inlining entirely (viewerCoreSource may be nil), exactly one occurrence requires a
    /// non-nil source and splices it in with only the `export ` keyword stripped from its
    /// top-level declarations (nothing else about the file's text changes), more than one
    /// occurrence of EITHER placeholder always throws regardless of source. The JSON itself
    /// is embedded as-is (GraphJSON.encode already produces ASCII-safe, non-pretty-printed
    /// output) with every `</` escaped to `<\/` so a person or group name containing
    /// `</script>` cannot close the tag it is embedded inside.
    public static func build(template: String, viewerCoreSource: String?, graphJSON: Data) throws -> String {
        // __GRAPH_JSON__: unconditional, every template shape renders some graph.
        try assertAppearsExactlyOnce(jsonPlaceholder, in: template)

        // __VIEWER_CORE_JS__: conditional on the template. Zero occurrences (template-sky.html)
        // skips core inlining entirely -- a nil source is fine, there is nowhere to splice it.
        // Exactly one occurrence (template-v4.html) requires a real source. More than one is
        // always an error, independent of what the caller passed for the source.
        let coreCount = occurrenceCount(of: corePlaceholder, in: template)
        var result = template
        if coreCount > 1 {
            throw BuildError.placeholderAppearsMultipleTimes(corePlaceholder, count: coreCount)
        } else if coreCount == 1 {
            guard let viewerCoreSource else {
                throw BuildError.viewerCoreSourceRequired
            }
            let strippedCore = viewerCoreSource.replacing(exportStripRegex()) { match in
                match.output[1].substring ?? ""
            }
            result = result.replacingOccurrences(of: corePlaceholder, with: strippedCore)
        }

        var payload = String(decoding: graphJSON, as: UTF8.self)
        payload = payload.replacingOccurrences(of: "</", with: "<\\/")
        result = result.replacingOccurrences(of: jsonPlaceholder, with: payload)

        return result
    }

    /// components(separatedBy:).count - 1 counts non-overlapping occurrences, the same thing
    /// build.py's str.count(placeholder) counts.
    private static func occurrenceCount(of placeholder: String, in template: String) -> Int {
        template.components(separatedBy: placeholder).count - 1
    }

    private static func assertAppearsExactlyOnce(_ placeholder: String, in template: String) throws {
        let count = occurrenceCount(of: placeholder, in: template)
        if count == 0 {
            throw BuildError.placeholderMissing(placeholder)
        }
        if count > 1 {
            throw BuildError.placeholderAppearsMultipleTimes(placeholder, count: count)
        }
    }
}
