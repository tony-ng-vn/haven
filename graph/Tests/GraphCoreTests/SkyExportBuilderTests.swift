import XCTest
@testable import GraphCore

final class SkyExportBuilderTests: XCTestCase {
    func testSubstitutesPlaceholderWithJSON() throws {
        let template = "<html><script>const RAW = __GRAPH_JSON__;</script></html>"
        let json = Data(#"{"nodes":[],"edges":[]}"#.utf8)

        let html = try SkyExportBuilder.build(template: template, graphJSON: json)

        XCTAssertFalse(html.contains("__GRAPH_JSON__"))
        XCTAssertTrue(html.contains(#"const RAW = {"nodes":[],"edges":[]};"#))
    }

    func testEscapesClosingScriptTagInsideAName() throws {
        let template = "const RAW = __GRAPH_JSON__;"
        // A name field that happens to contain "</script>" must not be able to close the
        // real <script> tag it will be embedded inside.
        let json = Data(#"{"nodes":[{"name":"</script><script>alert(1)"}]}"#.utf8)

        let html = try SkyExportBuilder.build(template: template, graphJSON: json)

        XCTAssertFalse(html.contains("</script><script>"))
        XCTAssertTrue(html.contains(#"<\/script><script>"#))
    }

    func testThrowsWhenPlaceholderIsMissing() {
        let template = "<html>no placeholder here</html>"
        let json = Data(#"{"nodes":[],"edges":[]}"#.utf8)

        XCTAssertThrowsError(try SkyExportBuilder.build(template: template, graphJSON: json)) { error in
            XCTAssertEqual(error as? SkyExportBuilder.BuildError, .placeholderMissing)
        }
    }
}
