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

    /// The name `recordOnboardingStep` takes.
    var recordName: String {
        switch self {
        case .name: return "name"
        case .location: return "location"
        case .contact: return "contact"
        }
    }
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
        // Onboarding happening once is now a fact the server holds, so clearing
        // a field on My Card no longer drops somebody back into the questions.
        // Before this record existed there was nothing to tell "never asked"
        // from "asked and answered, then emptied", and the flow guessed wrong.
        if card?.onboarding?.completedAt != nil { return nil }
        let filled = card?.filledSlots ?? []
        if !filled.contains(.name) { return .name }
        if !filled.contains(.city), !skipped.contains(.location) { return .location }
        if !filled.contains(.primaryContact), !skipped.contains(.contact) { return .contact }
        return nil
    }
}

/// Reconciling the device's record of what was skipped with the server's.
///
/// The device store used to be the record. It is a cache of this one now: a
/// skip made offline still has to survive the app being killed, and a skip made
/// on a phone that has since been wiped still has to be honoured on the next
/// one. Neither store is authoritative on its own, so both are read and the
/// device pushes anything the server has not heard.
enum OnboardingProgress {
    /// Every question this person has passed on, according to both stores.
    ///
    /// A union rather than a winner: the server knows about other devices, and
    /// the device knows about a skip whose write has not landed yet. Only
    /// `skipped` counts -- an answered question is already covered by its
    /// filled field, and treating it as decided here would keep a question
    /// unasked after the field it fills was cleared.
    static func skipped(
        in card: MyCard?,
        onDevice deviceSkips: Set<OnboardingStep>
    ) -> Set<OnboardingStep> {
        guard let onboarding = card?.onboarding else { return deviceSkips }
        let recorded = OnboardingStep.allCases.filter { onboarding.state(of: $0) == .skipped }
        return deviceSkips.union(recorded)
    }

    /// The skips the server has not been told about yet.
    ///
    /// The retry. A skip made with no signal, or on a build before this record
    /// existed, is pushed the next time the card loads rather than lost.
    static func unrecorded(
        onDevice deviceSkips: Set<OnboardingStep>,
        in card: MyCard?
    ) -> [OnboardingStep] {
        // Name can never be skipped -- the server refuses to record it, and
        // sending one would be an error on every launch forever.
        deviceSkips
            .filter { $0 != .name && card?.onboarding?.state(of: $0) == nil }
            .sorted { $0.rawValue < $1.rawValue }
    }
}

/// Questions this person passed on, kept on the device.
///
/// This was the record. It is a cache of `profiles.onboarding` now: the server
/// grew a field for "asked and declined" precisely because a skipped city and a
/// city nobody got round to asking for leave the same empty field. The cache
/// still earns its keep -- a skip made with no signal has to survive the app
/// being killed, and it is what `OnboardingProgress.unrecorded` retries from.
/// Keyed by user so a second account on the same phone starts clean.
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
    /// The avatar an authorization handed back, waiting for its contact answer
    /// to land.
    private var pendingAvatar: String?
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
        // After the answer, not beside it. Both are writes to the same row, and
        // running them together would mean one of them losing the `committing`
        // guard and reporting a failure that was really a collision.
        await importAvatar()
    }

    /// Holds the avatar a provider handed back, for `saveContact` to import
    /// once the contact answer itself has landed.
    ///
    /// Remembered rather than imported on the spot because an authorization can
    /// be followed by a panel, a correction, and a Continue -- and the photo
    /// should arrive with the answer, not during the editing of it.
    func rememberAvatar(_ url: String?) {
        pendingAvatar = url
    }

    /// Brings the provider's avatar into Haven's own storage.
    ///
    /// Only when there is no photo yet. Every successful authorization returns
    /// one, and a person who has already chosen a photo has said what they want
    /// their card to show; a payload is not an argument against that. Haven
    /// cannot tell a photo somebody picked from one it imported, so it never
    /// replaces either.
    ///
    /// Silent throughout. A failed import leaves the photo star unlit, which is
    /// the state the person was already in, and My Card's photo row is right
    /// there. Nothing here is worth interrupting the reveal for.
    func importAvatar() async {
        guard let source = pendingAvatar, let url = URL(string: source) else { return }
        guard card?.hasPhoto == false else {
            pendingAvatar = nil
            return
        }
        guard let data = await Self.download(url), let contentType = ImageFormat.contentType(of: data)
        else { return }
        pendingAvatar = nil
        let work = Task { () throws -> MyCard in
            let target: String = try await convex.mutation("profiles:generateUploadUrl")
            let storageId = try await PhotoUpload.send(data, to: target, contentType: contentType)
            return try await convex.mutation(
                "profiles:updateMyProfile",
                with: ["photoStorageId": storageId]
            )
        }
        guard let saved = await work.value(within: .seconds(HavenNetwork.deadline)) else { return }
        card = saved
    }

    private static func download(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return data
    }

    /// Passes on a question. Recorded on the device rather than sent, because
    /// the card has nowhere to say "asked and declined"; the unlit star on My
    /// Card is the whole nudge, and it comes from the missing field itself.
    func skip(_ step: OnboardingStep) {
        guard !committing else { return }
        skipped.insert(step)
        // The device write first and unconditionally: it is what makes a skip
        // survive a kill, and it is the retry queue for the record below.
        OnboardingSkips.save(skipped, userId: userId)
        record(step, as: "skipped")
        self.step = OnboardingStep.first(unansweredIn: card, skipped: skipped)
    }

    /// Tells the server what happened to a question.
    ///
    /// Never awaited by the flow. A record that does not land must not hold up
    /// the next question -- the answer itself is already saved, and the record
    /// is caught up by `reconcile` on the next launch.
    private func record(_ step: OnboardingStep, as state: String) {
        Task {
            let _: String? = try? await convex.mutation(
                "profiles:recordOnboardingStep",
                with: ["step": step.recordName, "state": state]
            )
        }
    }

    /// Pushes anything the device knows and the server does not.
    ///
    /// The catch-up for a skip made offline, and for every skip made by a build
    /// that shipped before this record existed.
    private func reconcile(against card: MyCard?) {
        for step in OnboardingProgress.unrecorded(onDevice: skipped, in: card) {
            record(step, as: "skipped")
        }
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
        let saved = await write.value(within: .seconds(HavenNetwork.deadline))
        isSaving = false
        guard let saved else {
            failure = "That did not save. Check your connection and try again."
            return
        }
        await commit(saved)
    }

    private func loadCard() {
        cancellable = HavenNetwork.subscribe(
            to: "profiles:getMyCard",
            yielding: MyCard?.self,
            // While onboarding runs this device is the sole writer, and every
            // commit hands back the new card. A live subscription would add a
            // second, later source that can move someone off the question they
            // are in the middle of answering.
            firstValueOnly: true
        ) { [weak self] card in
            guard let self else { return }
            self.card = card
            // Both stores, then the catch-up. A skip recorded on another phone
            // has to be honoured here, and a skip made here while offline has
            // to reach the server eventually.
            self.skipped = OnboardingProgress.skipped(in: card, onDevice: self.skipped)
            OnboardingSkips.save(self.skipped, userId: self.userId)
            self.reconcile(against: card)
            self.step = OnboardingStep.first(unansweredIn: card, skipped: self.skipped)
            self.load = .ready
        } onSilence: { [weak self] in
            guard let self, self.load == .loading else { return }
            self.load = .unreachable
        }
    }

    /// Publishes the new card, then the new question. The two are separate beats
    /// on purpose: publish both together and the next question replaces the
    /// screen before the star the person just earned ever reaches their eyes.
    private func commit(_ saved: MyCard) async {
        card = saved
        commits += 1
        // Recorded from the question that was on screen, not guessed from which
        // field changed: an answer and the question it answers are the same
        // event, and a later edit to the same field is not.
        if let answered = step { record(answered, as: "answered") }
        // The same beat `HavenScreen.ignite` waits, from the same constant.
        // Two sleeps because they are two different jobs -- one settles the
        // figure, this one holds the next question back -- but they must not
        // drift, so neither owns the number.
        try? await Task.sleep(for: .seconds(HavenMotion.starIgnitionHold))
        step = OnboardingStep.first(unansweredIn: saved, skipped: skipped)
    }
}
