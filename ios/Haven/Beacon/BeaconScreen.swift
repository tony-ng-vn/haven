import Combine
import ConvexMobile
import SwiftUI

/// Screen 9 of `../../phase1-build-plan.md`: the code someone else points a
/// camera at.
///
/// Unreachable while `FeatureFlags.beaconEnabled` is false, which it stays
/// until the page at `inhavens.com/<handle>` exists. A code that lands on a 404
/// is worse than no code.
struct BeaconScreen: View {
    @StateObject private var model: BeaconModel

    @HavenReduceMotion private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// What the screen was at before we raised it. Nil means we never raised
    /// it, so there is nothing to put back.
    @State private var previousBrightness: CGFloat?

    init() {
        _model = StateObject(wrappedValue: BeaconModel())
    }

    /// A loaded screen that never opens a socket, for previews.
    init(preview load: BeaconLoad) {
        _model = StateObject(wrappedValue: BeaconModel(preview: load))
    }

    var body: some View {
        HavenScreen(
            header: { EmptyView() },
            content: { content },
            actions: { EmptyView() }
        )
        .onAppear { raiseBrightness() }
        .onDisappear { restoreBrightness() }
        // Leaving the app is leaving the screen as far as brightness is
        // concerned. Without this, backgrounding mid-beacon leaves the phone
        // at full brightness for everything that comes after it.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                raiseBrightness()
            } else {
                restoreBrightness()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.load {
        case .loading:
            ProgressView()
                .tint(HavenColor.ink)
                .frame(maxWidth: .infinity)
        case .unreachable:
            VStack(spacing: 10) {
                Text("Haven could not load your beacon.")
                    .havenBody()
                Text("This is a connection problem. Your address has not changed.")
                    .havenSecondary()
                    .multilineTextAlignment(.center)
                GhostButton(title: "Try again") { model.retry() }
            }
            .frame(maxWidth: .infinity)
        case .ready(let card):
            beacon(for: card)
        }
    }

    private func beacon(for card: MyCard) -> some View {
        VStack(spacing: 20) {
            QRCodeView(text: BeaconAddress.url(for: card.username))
            VStack(spacing: 6) {
                if let name = card.name, !name.isEmpty {
                    Text(name)
                        .personName(.card)
                        .foregroundStyle(HavenColor.ink)
                }
                Text(BeaconAddress.display(for: card.username))
                    .havenMono()
            }
            Text("Show this. They point a camera and land on your card.")
                .havenSecondary()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// A code is read off a screen by a camera, and a dim screen is the most
    /// common reason that fails, so the screen goes bright while it is up.
    ///
    /// Skipped in Low Power Mode, where someone has explicitly asked the phone
    /// to spend less, and under Reduce Motion, where a sudden jump in
    /// brightness is the kind of abrupt change that setting exists to avoid.
    /// A slightly harder scan beats overriding either of those.
    private func raiseBrightness() {
        guard previousBrightness == nil else { return }
        guard !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        guard let screen = UIApplication.shared.havenScreen else { return }
        previousBrightness = screen.brightness
        screen.brightness = 1
    }

    private func restoreBrightness() {
        guard let previous = previousBrightness else { return }
        UIApplication.shared.havenScreen?.brightness = previous
        previousBrightness = nil
    }
}

private extension UIApplication {
    /// The screen this app is actually on. `UIScreen.main` is deprecated and
    /// wrong the moment the app is on an external display or in a second
    /// window.
    var havenScreen: UIScreen? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }
}

/// The code itself, drawn square-edged.
///
/// `.interpolation(.none)` is the whole trick: a QR scaled with smoothing turns
/// every module boundary into a gradient, and a camera then has to decide where
/// black stops. Nearest-neighbour keeps the edges where the generator put them.
private struct QRCodeView: View {
    let text: String

    var body: some View {
        Group {
            if let code = QRCode.image(for: text) {
                Image(decorative: code, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    // The quiet zone the QR spec asks for, in the code's own
                    // light tone so the margin is part of the panel rather than
                    // a gap the night shows through.
                    .padding(BeaconMetrics.quietZone)
                    .background(HavenColor.ink, in: RoundedRectangle(cornerRadius: 16))
            } else {
                Text("The code could not be drawn.")
                    .havenSecondary()
            }
        }
        .frame(width: BeaconMetrics.size, height: BeaconMetrics.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your beacon code")
    }
}

enum BeaconMetrics {
    /// Big enough to scan across a table, small enough to leave the name and
    /// the address room under it on the shortest phone Haven supports.
    static let size: CGFloat = 260
    /// The margin the QR spec asks for around a code. Without it a decoder has
    /// nothing to tell the code apart from whatever it is sitting on.
    static let quietZone: CGFloat = 16
}

// MARK: - Model

enum BeaconLoad: Equatable {
    case loading
    case ready(MyCard)
    case unreachable
}

/// Reads the caller's card for the one field the beacon needs: their handle.
@MainActor
final class BeaconModel: ObservableObject {
    @Published private(set) var load: BeaconLoad = .loading

    private var cancellable: AnyCancellable?

    private static let networkDeadline: TimeInterval = 12

    init() {
        subscribe()
    }

    init(preview load: BeaconLoad) {
        self.load = load
    }

    func retry() {
        load = .loading
        subscribe()
    }

    private func subscribe() {
        cancellable = convex
            .subscribe(to: "profiles:getMyCard", yielding: MyCard?.self)
            .timeout(.seconds(Self.networkDeadline), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.load == .loading else { return }
                self.load = .unreachable
            } receiveValue: { [weak self] card in
                // No card is not an empty beacon: the handle is minted when the
                // card is created, so a person with no card has not finished
                // onboarding and cannot be here.
                self?.load = card.map { .ready($0) } ?? .unreachable
            }
    }
}

// MARK: - Previews

private let previewCard = MyCard(username: "mayachen", name: "Maya Chen")

#Preview("Beacon") {
    NavigationStack {
        BeaconScreen(preview: .ready(previewCard))
    }
}

#Preview("Beacon, unreachable") {
    NavigationStack {
        BeaconScreen(preview: .unreachable)
    }
}

#Preview("Beacon, accessibility XXXL") {
    NavigationStack {
        BeaconScreen(preview: .ready(previewCard))
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Beacon, Reduce Motion") {
    NavigationStack {
        BeaconScreen(preview: .ready(previewCard))
    }
    .havenReduceMotion()
}
