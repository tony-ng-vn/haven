import SwiftUI

/// One way to open the legal pages, shared by every surface that offers them.
///
/// Welcome, My Card and the People menu all lead here, and they go through this
/// modifier rather than each presenting their own thing, for the same reason
/// `LegalDocument` builds its addresses from `Config.cardHost`: a second place
/// to decide is the first place to forget.
///
/// The prose lives once, on the site (`src/LegalPage.tsx`), and `SafariPage`
/// shows that page rather than a Swift copy of it. Two copies of a privacy
/// policy is two policies: the App Store listing points at the web one, so a
/// drift would mean the document under review and the document in the app
/// disagree about how somebody's notes are handled.
extension View {
    func legalSheet(_ document: Binding<LegalDocument?>) -> some View {
        // `LegalDocument` is already `Identifiable`, so the binding carries
        // which page to show as well as whether to show one.
        sheet(item: document) { SafariPage(url: $0.url) }
    }
}
