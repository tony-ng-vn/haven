import Combine
import ConvexMobile
import SwiftUI

/// The caller's own card, as `profiles:getMyCard` and `profiles:updateMyProfile`
/// both return it. Convex also sends `_id`, `_creationTime` and `updatedAt`;
/// onboarding has no use for any of them, and an unknown key is ignored.
struct MyCard: Decodable, Equatable {
    let username: String
    var name: String?
    var photoStorageId: String?
    var city: City?
    var handles: [Handle]?
    var primaryPlatform: Platform?
    var company: String?
    var role: String?

    struct City: Decodable, Equatable {
        let name: String
        var admin: String?
        var country: String?
    }

    struct Handle: Decodable, Equatable {
        let platform: Platform
        let value: String
        let verified: Bool
    }

    /// Mirrors `platformValidator` in `convex/profileFields.ts`. Email is absent
    /// on purpose: it was cut as a platform and nothing reintroduces it.
    enum Platform: String, Decodable, Equatable {
        case instagram, x, linkedin, phone
    }
}

extension MyCard {
    /// Which figure stars this card has earned. The slot mapping is fixed in
    /// `StarSlot`, so a field always lights the same star.
    var filledSlots: Set<StarSlot> {
        var slots: Set<StarSlot> = []
        if name?.isEmpty == false { slots.insert(.name) }
        if city != nil { slots.insert(.city) }
        if handles?.isEmpty == false { slots.insert(.primaryContact) }
        if photoStorageId != nil { slots.insert(.photo) }
        if company?.isEmpty == false { slots.insert(.company) }
        if role?.isEmpty == false { slots.insert(.role) }
        return slots
    }
}

/// A city on its way to the server.
///
/// Separate from `MyCard.City` on purpose: what we send and what comes back are
/// different contracts, and the stored city carries a private filter key that
/// the client never writes.
struct CityInput: Equatable {
    var name: String
    var admin: String?
    var country: String?
}

extension CityInput {
    /// The parts worth sending.
    ///
    /// Missing parts are left out rather than sent as null, because Convex's
    /// `v.optional` accepts an absent key and not an explicit null. Blank ones
    /// go too: MapKit hands back an empty admin area for countries that have no
    /// states, and a blank stored is a blank the card would render.
    var presentFields: [String: String] {
        var fields = ["name": name]
        if let admin, !admin.isEmpty { fields["admin"] = admin }
        if let country, !country.isEmpty { fields["country"] = country }
        return fields
    }

    var convexArgument: [String: ConvexEncodable?] {
        presentFields.mapValues { $0 as ConvexEncodable? }
    }
}

/// The three onboarding questions, in order.
enum OnboardingStep: Int, CaseIterable {
    case name
    case location
    case contact
}

extension OnboardingStep {
    /// The first question this card has not answered, or nil once onboarding is
    /// over. Derived from the card rather than from a counter, so a reinstall or
    /// an edit made on another device resumes in the right place.
    ///
    /// Name is not checked against `skipped`: it is the one required answer, and
    /// nothing offers to skip it.
    static func first(
        unansweredIn card: MyCard?,
        skipped: Set<OnboardingStep> = []
    ) -> OnboardingStep? {
        let filled = card?.filledSlots ?? []
        if !filled.contains(.name) { return .name }
        if !filled.contains(.city), !skipped.contains(.location) { return .location }
        if !filled.contains(.primaryContact), !skipped.contains(.contact) { return .contact }
        return nil
    }
}

/// Questions this person passed on, kept on the device.
///
/// A skip is a local decision, not a fact about the card. The server has no
/// field for "asked and declined", and adding one would make a skipped city
/// indistinguishable from one nobody has got round to asking for. Keyed by user
/// so a second account on the same phone starts clean.
enum OnboardingSkips {
    static func load(userId: String) -> Set<OnboardingStep> {
        let stored = UserDefaults.standard.array(forKey: key(userId)) as? [Int] ?? []
        return Set(stored.compactMap(OnboardingStep.init(rawValue:)))
    }

    static func save(_ steps: Set<OnboardingStep>, userId: String) {
        UserDefaults.standard.set(steps.map(\.rawValue).sorted(), forKey: key(userId))
    }

    private static func key(_ userId: String) -> String {
        "haven.onboarding.skipped.\(userId)"
    }
}

/// Whether the flow knows where the person is yet.
enum OnboardingLoad: Equatable {
    case loading
    case ready
    /// The card could not be read, so there is no telling which question is
    /// unanswered. Guessing would either repeat a question or skip one, and both
    /// are worse than saying so and offering to try again.
    case unreachable
}

/// Drives onboarding: the card as it stands, which question is on screen, and
/// the one sky every screen in the flow draws.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var load: OnboardingLoad = .loading
    /// What the card holds. Drives the figure, so a committed field lights its
    /// star the moment the write lands.
    @Published private(set) var card: MyCard?
    /// Which question is on screen. Follows `card`, except straight after a
    /// commit, where it is held back for the ignition (see `commit`).
    @Published private(set) var step: OnboardingStep?
    @Published private(set) var isSaving = false
    /// Counts answers committed on this device. It drives the commit haptic,
    /// which has to fire for a write the person just made and never for state
    /// that merely arrived -- a resumed session opens with its stars already lit.
    @Published private(set) var commits = 0
    @Published var failure: String?

    /// Built once and shared by every onboarding screen. Generating a sky walks
    /// 150 stars and a minimum spanning tree, which is not work to redo per
    /// screen -- and the figure has to be the same one throughout.
    let sky: Sky

    private let userId: String
    private var skipped: Set<OnboardingStep> = []
    private var cancellable: AnyCancellable?

    /// - Parameter userId: the Clerk user id. It is the seed for the whole
    ///   constellation: names collide and change, and the profile row does not
    ///   exist yet on the first question, where the figure is already on screen.
    init(userId: String) {
        self.userId = userId
        sky = SkyGenerator.build(seed: userId)
        skipped = OnboardingSkips.load(userId: userId)
        loadCard()
    }

    /// A loaded flow that never opens a socket. SwiftUI previews are how every
    /// Haven screen is reviewed, and a preview cannot reach Convex.
    init(previewUserId userId: String, card: MyCard? = nil) {
        self.userId = userId
        sky = SkyGenerator.build(seed: userId)
        self.card = card
        step = OnboardingStep.first(unansweredIn: card)
        load = .ready
    }

    var litMajors: Set<Int> {
        StarSlot.litMajorIndices(
            filled: card?.filledSlots ?? [],
            majorCount: sky.majors.count
        )
    }

    func retry() {
        load = .loading
        loadCard()
    }

    /// Commits the name and lights the first star.
    func saveName(_ raw: String) async {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await save(["name": name])
    }

    /// Commits the city and lights the second star.
    func saveCity(_ city: CityInput) async {
        guard !city.name.isEmpty else { return }
        await save(["city": city.convexArgument])
    }

    /// Passes on a question. Recorded on the device rather than sent, because
    /// the card has nowhere to say "asked and declined"; the unlit star on My
    /// Card is the whole nudge, and it comes from the missing field itself.
    func skip(_ step: OnboardingStep) {
        guard !isSaving else { return }
        skipped.insert(step)
        OnboardingSkips.save(skipped, userId: userId)
        self.step = OnboardingStep.first(unansweredIn: card, skipped: skipped)
    }

    private func save(_ fields: [String: ConvexEncodable?]) async {
        guard !isSaving else { return }
        failure = nil
        isSaving = true
        var saved: MyCard?
        do {
            let value: MyCard = try await convex.mutation(
                "profiles:updateMyProfile",
                with: fields
            )
            saved = value
        } catch {
            failure = "That did not save. Check your connection and try again."
        }
        isSaving = false
        guard let saved else { return }
        await commit(saved)
    }

    private func loadCard() {
        cancellable = convex
            .subscribe(to: "profiles:getMyCard", yielding: MyCard?.self)
            // The first value only. While onboarding runs this device is the
            // sole writer, and every commit hands back the new card; a live
            // subscription would just add a second, later source that can move
            // someone off the question they are in the middle of answering.
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure = completion { self?.load = .unreachable }
            } receiveValue: { [weak self] card in
                guard let self else { return }
                self.card = card
                self.step = OnboardingStep.first(unansweredIn: card, skipped: self.skipped)
                self.load = .ready
            }
    }

    /// Publishes the new card, then the new question. The two are separate beats
    /// on purpose: publish both together and the next question replaces the
    /// screen before the star the person just earned ever reaches their eyes.
    private func commit(_ saved: MyCard) async {
        card = saved
        commits += 1
        try? await Task.sleep(for: .seconds(HavenMotion.starIgnitionDuration))
        step = OnboardingStep.first(unansweredIn: saved, skipped: skipped)
    }
}
