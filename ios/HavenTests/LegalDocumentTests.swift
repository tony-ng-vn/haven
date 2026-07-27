import Foundation
import Testing
@testable import Haven

// The addresses App Review follows out of the app. A typo here is invisible in
// a build and fatal in a review, so the shape is asserted rather than trusted.

@Suite("Legal documents")
struct LegalDocumentTests {
    @Test("both documents point at the site the cards live on")
    func addresses() {
        #expect(
            LegalDocument.privacy.url.absoluteString
                == "https://\(Config.cardHost)/privacy"
        )
        #expect(
            LegalDocument.terms.url.absoluteString
                == "https://\(Config.cardHost)/terms"
        )
    }

    // The web router reads these two words off the path, so the case names and
    // the routes are one decision. Renaming a case silently breaks the link.
    @Test("the path is the case name, lowercased")
    func paths() {
        #expect(LegalDocument.privacy.rawValue == "privacy")
        #expect(LegalDocument.terms.rawValue == "terms")
    }

    @Test("every document is offered, and each reads as itself")
    func rows() {
        #expect(LegalDocument.allCases.count == 2)
        #expect(LegalDocument.privacy.title == "Privacy Policy")
        #expect(LegalDocument.terms.title == "Terms of Service")
        // Distinct ids, or SwiftUI's ForEach renders one row twice.
        #expect(Set(LegalDocument.allCases.map(\.id)).count == 2)
    }
}
