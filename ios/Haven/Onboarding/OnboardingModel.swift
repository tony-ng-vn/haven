import Combine
import ConvexMobile
import SwiftUI

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

/// The one way to be reached that onboarding asks for.
///
/// `verified` means the value itself was proven, not merely that an
/// authorization happened: X hands back the username, so it is verified, while
/// LinkedIn only proves the person and leaves the address hand-confirmed.
struct ChosenContact: Equatable {
    var platform: MyCard.Platform
    var value: String
    var verified: Bool
}

extension ChosenContact {
    var convexArgument: [String: ConvexEncodable?] {
        ["platform": platform.rawValue, "value": value, "verified": verified]
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
    /// True from the moment a write starts until the next question is on screen.
    /// Deliberately longer-lived than `isSaving`, which only drives the button's
    /// spinner: the question stays up through the star ignition, and a second
    /// tap in that window would fire the same write twice.
    private var committing = false
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

    /// Commits the one way to be reached and lights the third star.
    ///
    /// The handle list is sent whole because that is the shape the mutation
    /// takes, and onboarding collects exactly one. More ways to be reached are
    /// added later, on the card.
    func saveContact(_ contact: ChosenContact) async {
        guard !contact.value.isEmpty else { return }
        let handles: [ConvexEncodable?] = [contact.convexArgument]
        await save(["handles": handles, "primaryPlatform": contact.platform.rawValue])
    }

    /// Passes on a question. Recorded on the device rather than sent, because
    /// the card has nowhere to say "asked and declined"; the unlit star on My
    /// Card is the whole nudge, and it comes from the missing field itself.
    func skip(_ step: OnboardingStep) {
        guard !committing else { return }
        skipped.insert(step)
        OnboardingSkips.save(skipped, userId: userId)
        self.step = OnboardingStep.first(unansweredIn: card, skipped: skipped)
    }

    private func save(_ fields: [String: ConvexEncodable?]) async {
        guard !committing else { return }
        committing = true
        defer { committing = false }
        failure = nil
        isSaving = true
        let write = Task { () throws -> MyCard in
            try await convex.mutation("profiles:updateMyProfile", with: fields)
        }
        // Bounded for the same reason the read is: a write with no network sits
        // in the client's reconnect loop instead of failing, and a Continue
        // button that spins forever is worse than one that says what happened.
        // The wait is what ends, not the write -- if it lands late, the next
        // attempt overwrites it with the same values.
        let saved = await write.value(within: .seconds(Self.networkDeadline))
        isSaving = false
        guard let saved else {
            failure = "That did not save. Check your connection and try again."
            return
        }
        await commit(saved)
    }

    /// Long enough for a slow connection, short enough that a dead one does not
    /// hold the screen.
    private static let networkDeadline: TimeInterval = 12

    private func loadCard() {
        cancellable = convex
            .subscribe(to: "profiles:getMyCard", yielding: MyCard?.self)
            // The first value only. While onboarding runs this device is the
            // sole writer, and every commit hands back the new card; a live
            // subscription would just add a second, later source that can move
            // someone off the question they are in the middle of answering.
            .first()
            // The Convex client reconnects rather than failing, so a read with
            // no network does not error -- it waits. Nothing else would ever end
            // that wait, and an onboarding that opens on a spinner forever is
            // the one outcome with no way out of it.
            .timeout(.seconds(Self.networkDeadline), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Any ending counts, not just a failure: a timeout finishes the
                // stream without a value, so still being in `.loading` here is
                // what "we never heard back" looks like.
                guard let self, self.load == .loading else { return }
                self.load = .unreachable
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
