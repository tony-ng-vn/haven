import SafariServices
import SwiftUI

/// One way to open the legal pages, shared by every surface that offers them.
///
/// Welcome, My Card and the People menu all lead here, and they go through this
/// modifier rather than each presenting their own thing, for the same reason
/// `LegalDocument` builds its addresses from `Config.cardHost`: a second place
/// to decide is the first place to forget.
extension View {
    func legalSheet(_ document: Binding<LegalDocument?>) -> some View {
        // `LegalDocument` is already `Identifiable`, so the binding carries
        // which page to show as well as whether to show one.
        sheet(item: document) { SafariPage(url: $0.url) }
    }
}

/// The web page, shown inside Haven.
///
/// The prose lives once, on the site (`src/LegalPage.tsx`), and this shows that
/// page rather than a Swift copy of it. Two copies of a privacy policy is two
/// policies: the App Store listing points at the web one, so a drift would mean
/// the document under review and the document in the app disagree about how
/// somebody's notes are handled.
///
/// `SFSafariViewController` rather than a bare `WKWebView` because it arrives
/// with a Done button, a reload and a share sheet already built, and reloading
/// is the one thing this page needs when it opens with no signal.
private struct SafariPage: UIViewControllerRepresentable {
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

    // Nothing to update: the sheet is rebuilt when the bound document changes,
    // and a document is the only thing this page has to say.
    func updateUIViewController(_ page: SFSafariViewController, context: Context) {}
}
