import Combine
import Foundation

struct PersonEvent: Decodable, Equatable, Identifiable {
    let _id: String
    let title: String
    let startedAt: Double
    let endedAt: Double?

    var id: String { _id }
    var startDate: Date { Date(timeIntervalSince1970: startedAt / 1_000) }
}

@MainActor
final class PersonEventModel: ObservableObject {
    @Published private(set) var events: [PersonEvent]
    private var cancellable: AnyCancellable?

    init(personId: String) {
        events = []
        cancellable = HavenNetwork.subscribe(
            to: "events:listForPerson",
            with: ["personId": personId],
            yielding: [PersonEvent].self
        ) { [weak self] events in
            self?.events = events
        } onSilence: {
            // An empty list and an unreachable list render the same absence;
            // the person's core data still owns the screen-level retry.
        }
    }

    init(preview events: [PersonEvent] = []) {
        self.events = events
    }
}
