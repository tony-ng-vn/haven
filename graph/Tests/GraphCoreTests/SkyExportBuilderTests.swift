import XCTest
@testable import GraphCore

final class SkyExportBuilderTests: XCTestCase {

    // A small synthetic core string, not the real bundled viewer_core.mjs (matching how the
    // rest of this file already works with a synthetic template) -- but built from two REAL
    // top-level declarations that actually exist in viewer/viewer_core.mjs, so "contains a
    // known function name from viewer_core.mjs" is anchored to the real file, not made up.
    private let syntheticCoreSource = """
    export function adaptRaw(raw) {
        return raw;
    }
    export const DEFAULT_LAYOUT_SEED = 20260731;
    """

    private let syntheticTemplate = "<html><script>__VIEWER_CORE_JS__\nconst RAW = __GRAPH_JSON__;</script></html>"

    func testSubstitutesBothPlaceholdersWithStrippedCoreAndJSON() throws {
        let json = Data(#"{"nodes":[],"edges":[]}"#.utf8)

        let html = try SkyExportBuilder.build(template: syntheticTemplate, viewerCoreSource: syntheticCoreSource, graphJSON: json)

        XCTAssertFalse(html.contains("__VIEWER_CORE_JS__"), "neither placeholder may survive")
        XCTAssertFalse(html.contains("__GRAPH_JSON__"), "neither placeholder may survive")
        XCTAssertTrue(html.contains("adaptRaw"), "a known function name from viewer_core.mjs must appear in the built output")
        XCTAssertTrue(html.contains(#"const RAW = {"nodes":[],"edges":[]};"#), "the injected JSON must appear in the built output")
    }

    func testNoLineBeginningWithExportSurvivesTheStrip() throws {
        let json = Data(#"{"nodes":[],"edges":[]}"#.utf8)

        let html = try SkyExportBuilder.build(template: syntheticTemplate, viewerCoreSource: syntheticCoreSource, graphJSON: json)

        let survivingExportLines = html
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("export ") }
        XCTAssertTrue(survivingExportLines.isEmpty, "no line beginning with \"export \" may survive the strip")
        XCTAssertTrue(html.contains("function adaptRaw(raw) {"), "export must be stripped, the rest of the declaration untouched")
        XCTAssertTrue(html.contains("const DEFAULT_LAYOUT_SEED = 20260731;"), "export must be stripped, the rest of the declaration untouched")
    }

    func testEscapesClosingScriptTagInsideAName() throws {
        // A name field that happens to contain "</script>" must not be able to close the
        // real <script> tag it will be embedded inside.
        let json = Data(#"{"nodes":[{"name":"</script><script>alert(1)"}]}"#.utf8)

        let html = try SkyExportBuilder.build(template: syntheticTemplate, viewerCoreSource: syntheticCoreSource, graphJSON: json)

        XCTAssertFalse(html.contains("</script><script>alert"))
        XCTAssertTrue(html.contains(#"<\/script><script>alert"#))
    }

    func testThrowsWhenCorePlaceholderIsMissing() {
        let template = "<html><script>\nconst RAW = __GRAPH_JSON__;</script></html>"
        let json = Data(#"{"nodes":[],"edges":[]}"#.utf8)

        XCTAssertThrowsError(try SkyExportBuilder.build(template: template, viewerCoreSource: syntheticCoreSource, graphJSON: json)) { error in
            XCTAssertEqual(error as? SkyExportBuilder.BuildError, .placeholderMissing("__VIEWER_CORE_JS__"))
        }
    }

    func testThrowsWhenJSONPlaceholderIsMissing() {
        let template = "<html><script>__VIEWER_CORE_JS__\nconst RAW = 1;</script></html>"
        let json = Data(#"{"nodes":[],"edges":[]}"#.utf8)

        XCTAssertThrowsError(try SkyExportBuilder.build(template: template, viewerCoreSource: syntheticCoreSource, graphJSON: json)) { error in
            XCTAssertEqual(error as? SkyExportBuilder.BuildError, .placeholderMissing("__GRAPH_JSON__"))
        }
    }

    func testThrowsWhenCorePlaceholderAppearsMultipleTimes() {
        let template = "<html><script>__VIEWER_CORE_JS__ __VIEWER_CORE_JS__\nconst RAW = __GRAPH_JSON__;</script></html>"
        let json = Data(#"{"nodes":[],"edges":[]}"#.utf8)

        XCTAssertThrowsError(try SkyExportBuilder.build(template: template, viewerCoreSource: syntheticCoreSource, graphJSON: json)) { error in
            XCTAssertEqual(error as? SkyExportBuilder.BuildError, .placeholderAppearsMultipleTimes("__VIEWER_CORE_JS__", count: 2))
        }
    }

    func testThrowsWhenJSONPlaceholderAppearsMultipleTimes() {
        let template = "<html><script>__VIEWER_CORE_JS__\nconst RAW = __GRAPH_JSON__; const RAW2 = __GRAPH_JSON__;</script></html>"
        let json = Data(#"{"nodes":[],"edges":[]}"#.utf8)

        XCTAssertThrowsError(try SkyExportBuilder.build(template: template, viewerCoreSource: syntheticCoreSource, graphJSON: json)) { error in
            XCTAssertEqual(error as? SkyExportBuilder.BuildError, .placeholderAppearsMultipleTimes("__GRAPH_JSON__", count: 2))
        }
    }
}
