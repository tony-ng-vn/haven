import SafariServices
import SwiftUI

/// A web page, shown inside Haven with the system browser's own chrome.
///
/// `SFSafariViewController` rather than a bare `WKWebView` because it arrives
/// with a Done button, a reload and a share sheet already built. Its own Done
/// button is why a page presented this way is one of the two documented
/// exceptions to `havenDismissable()` -- see that modifier's doc comment.
///
/// Shared by the legal pages (`LegalSheet.swift`) and Composio's connect flow
/// (`ContactConnector.swift`, `ContactScreen.swift`): both need a web page
/// inside a Haven-tinted browser, and a second copy of this wrapper is a
/// second place for the tinting to drift.
struct SafariPage: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let page = SFSafariViewController(url: url)
        // The app declares itself dark to the system, and Safari's chrome is
        // light by default: untinted, this arrives as a white slab over the
        // night gradient.
        page.preferredBarTintColor = UIColor(HavenColor.night)
        page.preferredControlTintColor = UIColor(HavenColor.star)
        page.dismissButtonStyle = .done
        return page
    }

    // Nothing to update: the sheet is rebuilt when the bound page changes,
    // and a URL is the only thing this page has to say.
    func updateUIViewController(_ page: SFSafariViewController, context: Context) {}
}
