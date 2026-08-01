import SwiftUI
import WebKit

/// Wraps the in-app WKWebView that renders the built sky HTML (template-v4.html with its
/// __VIEWER_CORE_JS__ and __GRAPH_JSON__ placeholders already substituted by
/// AppModel.finishMapping, via GraphCore.SkyExportBuilder). `allowingReadAccessTo` is the
/// file's own containing directory, not the file itself: the page's own JS is self-contained
/// (no relative asset references), but WKWebView requires the access-scope root to be a
/// directory, not the leaf file, or loadFileURL silently fails to load anything.
struct SkyView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // fileURL is stable for SkyView's lifetime (AppModel only ever writes a new sky.html
        // and this view is reconstructed alongside the onboardingStep transition into
        // .sky) -- re-loading on every SwiftUI update pass would restart the whole canvas
        // simulation on every unrelated toolbar re-render.
        if webView.url != fileURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }
    }
}
