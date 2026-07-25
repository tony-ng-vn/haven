import Combine
import MapKit

/// One city the completer offered. Two display strings and the completion they
/// came from; the structured fields only exist once `resolve` runs.
struct CitySuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion
}

/// Typeahead over MapKit for the location question.
///
/// Deliberately not `@MainActor`: `MKLocalSearchCompleterDelegate` is not
/// isolated, and MapKit already calls back on the main thread, so isolating the
/// class would buy an annotation mismatch and nothing else.
final class CityCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [CitySuggestion] = []

    private let completer = MKLocalSearchCompleter()

    /// Below this a query matches most of the world and the list is noise.
    private static let minimumQueryLength = 2
    private static let maximumSuggestions = 5

    override init() {
        super.init()
        completer.delegate = self
        // Places, not businesses. Without this a search for a city comes back
        // full of the coffee shops inside it.
        completer.resultTypes = .address
    }

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.minimumQueryLength else {
            clear()
            return
        }
        completer.queryFragment = query
    }

    func clear() {
        completer.cancel()
        completer.queryFragment = ""
        suggestions = []
    }

    /// Turns a chosen completion into the structured city the card stores.
    ///
    /// A second round trip, and worth it: the completion is two display strings,
    /// while Phase 3 filters on a real locality, admin area and country. Returns
    /// nil if the lookup fails, which the caller degrades to the typed text
    /// rather than treating as a dead end.
    func resolve(_ suggestion: CitySuggestion) async -> CityInput? {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        guard let placemark = try? await MKLocalSearch(request: request).start()
            .mapItems.first?.placemark
        else { return nil }
        // Falls back to the suggestion's own title when MapKit has no locality,
        // which is what happens for a region or a country picked on its own.
        return CityInput(
            name: placemark.locality ?? placemark.name ?? suggestion.title,
            admin: placemark.administrativeArea,
            country: placemark.country
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
            .filter(Self.looksLikeAPlace)
            .prefix(Self.maximumSuggestions)
            .map {
                CitySuggestion(
                    id: "\($0.title)|\($0.subtitle)",
                    title: $0.title,
                    subtitle: $0.subtitle,
                    completion: $0
                )
            }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // A failed completion is not worth a message. The person can still type
        // a city and continue, which is the escape hatch this screen needs
        // anyway for places MapKit does not know.
        suggestions = []
    }

    /// Keeps street addresses out of a screen that promises never to ask for
    /// one. A house number or a postcode puts a digit in the title, and no city
    /// name does.
    ///
    /// A heuristic, not a filter: iOS 18's `MKAddressFilter` is the real answer
    /// and should replace this once the deployment target passes 17.
    private static func looksLikeAPlace(_ completion: MKLocalSearchCompletion) -> Bool {
        !completion.title.contains(where: \.isNumber)
    }
}
