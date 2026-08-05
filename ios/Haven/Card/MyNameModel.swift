import Combine
import ConvexMobile
import SwiftUI

/// Just the caller's own first name, kept live for the People tab's title.
///
/// Deliberately not `MyCardModel`: that one also carries a photo upload,
/// claiming an address, and deleting the account, and hoisting it up to
/// `HavenTabs` would hand every screen under the tabs a live handle to
/// account deletion so the title could read a name. This subscribes to the
/// same `profiles:getMyCard` query -- the card is small, and a second read
/// of it is cheap next to a second write surface sitting where nothing
/// should be writing -- and keeps only the one field the title needs.
///
/// Owned by `HavenTabs`, which exists for the whole post-onboarding session,
/// so the title stays live if a name is edited on My Card mid-session rather
/// than freezing at whatever `OnboardingModel` last saw.
@MainActor
final class MyNameModel: ObservableObject {
    @Published private(set) var firstName: String?

    private var cancellable: AnyCancellable?

    init() {
        subscribe()
    }

    /// A name held from the start, for previews and tests -- never opens a
    /// socket.
    init(preview firstName: String?) {
        self.firstName = firstName
    }

    private func subscribe() {
        cancellable = HavenNetwork.subscribe(
            to: "profiles:getMyCard",
            yielding: MyCard?.self
        ) { [weak self] card in
            self?.firstName = PeopleTitle.firstName(of: card?.name)
        } onSilence: {
            // Nothing to fall back to beyond what is already showing:
            // `PeopleTitle` already reads a nil name as "Your Haven", which
            // is the honest title for a card that could not be read.
        }
    }
}
