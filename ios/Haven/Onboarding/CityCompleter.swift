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
        if #available(iOS 18.0, *) {
            // Cities, and only cities. Without it "San Francisco" also offers
            // San Francisco County, San Francisco Bay and a postal code, none
            // of which is an answer to "where are you based". Counties are
            // subAdministrativeArea and bays are not address components at all,
            // so including locality alone drops both.
            completer.addressFilter = MKAddressFilter(including: [.locality])
        }
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
    /// while Phase 3 filters on a real locality, admin area and country.
    ///
    /// Nil means "this is not a city": either the lookup failed, or the place
    /// has no locality, which is what a county, a bay or a landmark looks like
    /// from here. That second case is the only thing standing between the
    /// screen's promise and an iOS 17 device, where `addressFilter` does not
    /// exist and the digit check lets those through. Falling back to
    /// `placemark.name` would have quietly stored them as cities.
    func resolve(_ suggestion: CitySuggestion) async -> CityInput? {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        guard let placemark = try? await MKLocalSearch(request: request).start()
            .mapItems.first?.placemark,
            let locality = placemark.locality
        else { return nil }
        return CityInput(
            name: locality,
            admin: placemark.administrativeArea,
            country: placemark.country
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // MapKit can offer the same place twice, so the list is deduplicated on
        // the way in: two identical rows read as a bug, and identical ids would
        // break the list's identity besides.
        var seen: Set<String> = []
        suggestions = completer.results
            .filter(Self.looksLikeAPlace)
            .compactMap { result in
                let id = "\(result.title)|\(result.subtitle)"
                guard seen.insert(id).inserted else { return nil }
                return CitySuggestion(
                    id: id,
                    title: result.title,
                    subtitle: result.subtitle,
                    completion: result
                )
            }
            .prefix(Self.maximumSuggestions)
            .map { $0 }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // A failed completion is not worth a message. The person can still type
        // a city and continue, which is the escape hatch this screen needs
        // anyway for places MapKit does not know.
        suggestions = []
    }

    /// The iOS 17 stand-in for `addressFilter`, which does not exist there. A
    /// house number or a postcode puts a digit in the title and no city name
    /// does, so this keeps street addresses out; it cannot tell a county from a
    /// city, which is the part only the real filter gets right.
    ///
    /// Delete this, and the `#available` above it, if the deployment target ever
    /// moves past 17.
    private static func looksLikeAPlace(_ completion: MKLocalSearchCompletion) -> Bool {
        !completion.title.contains(where: \.isNumber)
    }
}
