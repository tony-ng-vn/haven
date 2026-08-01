import Foundation

/// Fills viewer/template-v3.html's `__GRAPH_JSON__` placeholder in-process, the app's own
/// equivalent of viewer/build.py -- a downloaded build ships with no Python and no repo
/// checkout, so this cannot shell out to the script; it has to do the same substitution
/// natively.
public enum SkyExportBuilder {
    public enum BuildError: Error, Equatable, Sendable {
        /// The bundled template is missing the placeholder entirely -- shipping it
        /// unsubstituted would be a JS syntax error and a blank canvas with no error
        /// surfaced anywhere, so this fails loudly instead.
        case placeholderMissing
    }

    private static let placeholder = "__GRAPH_JSON__"

    /// Mirrors build.py's own two rules exactly: JSON is embedded as-is (GraphJSON.encode
    /// already produces ASCII-safe, non-pretty-printed output), and every `</` is escaped
    /// to `<\/` so a person or group name containing `</script>` cannot close the tag it
    /// is embedded inside.
    public static func build(template: String, graphJSON: Data) throws -> String {
        guard template.contains(placeholder) else {
            throw BuildError.placeholderMissing
        }
        var payload = String(decoding: graphJSON, as: UTF8.self)
        payload = payload.replacingOccurrences(of: "</", with: "<\\/")
        return template.replacingOccurrences(of: placeholder, with: payload)
    }
}
