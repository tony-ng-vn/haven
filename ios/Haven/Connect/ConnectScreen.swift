import SwiftUI

/// Scanning somebody's card, and connecting to them.
///
/// The in-person loop, and the whole of Phase 4 from this side: I show you the
/// back of my card, you point your camera at it, and we are both in each
/// other's directories with a live card rather than a snapshot. The backend has
/// done both halves since PR 126 and nothing on iOS ever called it.
///
/// One thing at a time. While the camera is looking, that is the screen; the
/// moment there is a card it replaces the viewfinder, because a card somebody
/// is reading over a live camera is two things asking for the same attention.
struct ConnectScreen: View {
    /// Opens the person this connection landed. The caller owns navigation:
    /// this screen is a sheet, and the directory it came from is what holds the
    /// stack the person is pushed onto.
    var openPerson: (String) -> Void = { _ in }

    @StateObject private var model: ConnectModel
    @Environment(\.dismiss) private var dismiss
    @State private var photo: Image?

    init(openPerson: @escaping (String) -> Void = { _ in }) {
        self.openPerson = openPerson
        _model = StateObject(wrappedValue: ConnectModel())
    }

    /// A screen in a fixed state that never opens a socket, for previews.
    init(preview state: ConnectState, typed: String = "") {
        _model = StateObject(wrappedValue: ConnectModel(preview: state, typed: typed))
    }

    var body: some View {
        HavenScreen(
            question: question,
            hint: hint,
            contentAlignment: .top
        ) {
            content
        } actions: {
            actions
        }
        .presentationDragIndicator(.visible)
    }

    private var question: String {
        switch model.state {
        case .connected: return "Connected"
        default: return "Connect"
        }
    }

    private var hint: String? {
        switch model.state {
        case .idle, .looking:
            return CodeScanner.isSupported
                ? "Point at the code on the back of their card."
                : "Type the address on the back of their card."
        default:
            return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.state {
            case .idle, .looking:
                viewfinder
                typedAddress
                if model.state == .looking {
                    HStack(spacing: 10) {
                        ProgressView().tint(HavenColor.faint)
                        Text("Looking them up...")
                            .havenSecondary()
                    }
                    .accessibilityElement(children: .combine)
                }
            case .unknown(let handle):
                // The code scanned perfectly. There is just no card behind it,
                // which is a different thing from a scan that failed and gets
                // said differently.
                Text("\(BeaconAddress.display(for: handle)) is not a Haven card.")
                    .havenBody()
                typedAddress
            case .found(let card), .connecting(let card):
                preview(card)
            case .connected(let outcome, let card):
                preview(card)
                Text(
                    outcome.wasAlready
                        ? "You were already connected. They are in your people."
                        : "They are in your people, and you are in theirs."
                )
                .havenSecondary()
            case .failed(let message):
                Text(message)
                    .havenSecondary(HavenColor.ember)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .havenAnimation(HavenMotion.screen, value: model.state)
    }

    /// The camera, in a window rather than full bleed: this is a sheet over the
    /// directory, and a full-screen camera would read as leaving Haven for a
    /// scanning app.
    @ViewBuilder
    private var viewfinder: some View {
        if CodeScanner.isSupported {
            CodeScanner(isScanning: model.state.isScanning) { code in
                Task { await model.scanned(code) }
            }
            .frame(height: ConnectMetrics.viewfinderHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(HavenColor.hairline)
            )
            .accessibilityLabel("Camera, looking for a Haven code")
        }
    }

    /// The way in for everybody the camera cannot serve: a simulator, a phone
    /// whose camera was refused, an address read out over a table.
    private var typedAddress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CodeScanner.isSupported ? "Or type their address" : "Their address")
                .havenGroupLabel()
            HavenField(
                label: "Their Haven address",
                placeholder: "\(Config.cardHost)/theirname",
                text: $model.typed,
                capitalization: .never,
                submitLabel: .go,
                autofocus: !CodeScanner.isSupported,
                onSubmit: lookUpTyped
            )
        }
    }

    private func preview(_ card: PublicCard) -> some View {
        CardObject {
            HavenCard(card: card.asCard, sky: SkyGenerator.build(seed: card.handle), photo: photo)
        }
        .frame(maxWidth: .infinity)
        .cardPhoto(card.photoURL, into: $photo)
        // The card is who this is; VoiceOver gets the name and the address
        // rather than a figure it cannot see.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.name), \(BeaconAddress.display(for: card.handle))")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            switch model.state {
            case .idle, .looking:
                PrimaryButton(title: "Look them up", action: lookUpTyped)
                    .disabled(!model.canLookUpTyped)
                GhostButton(title: "Cancel") { dismiss() }
            case .unknown, .failed:
                GhostButton(title: "Try another") { model.reset() }
                GhostButton(title: "Cancel") { dismiss() }
            case .found(let card), .connecting(let card):
                PrimaryButton(
                    title: "Connect",
                    isLoading: model.state == .connecting(card)
                ) {
                    Task { await model.connect() }
                }
                GhostButton(title: "Not them") { model.reset() }
            case .connected(let outcome, _):
                PrimaryButton(title: "Open them") {
                    dismiss()
                    openPerson(outcome.personId)
                }
                GhostButton(title: "Done") { dismiss() }
            }
        }
    }

    private func lookUpTyped() {
        Task { await model.look(at: model.typed) }
    }
}

enum ConnectMetrics {
    /// Tall enough to hold a card at arm's length, short enough that the typed
    /// address is on screen under it without scrolling.
    static let viewfinderHeight: CGFloat = 260
}

// MARK: - Previews

private let previewCard = PublicCard(
    handle: "mayachen",
    name: "Maya Chen",
    city: MyCard.City(name: "Ho Chi Minh City", country: "Vietnam"),
    handles: [MyCard.Handle(platform: .x, value: "mayachen", verified: true)],
    primaryPlatform: .x
)

#Preview("Connect, looking") {
    ConnectScreen(preview: .idle)
}

#Preview("Connect, found somebody") {
    ConnectScreen(preview: .found(previewCard))
}

#Preview("Connect, nobody there") {
    ConnectScreen(preview: .unknown("mayachen"), typed: "inhavens.com/mayachen")
}

#Preview("Connect, connected") {
    ConnectScreen(
        preview: .connected(
            ConnectOutcome(status: "connected", personId: "p1", peerUsername: "mayachen"),
            previewCard
        )
    )
}

#Preview("Connect, accessibility XXXL") {
    ConnectScreen(preview: .found(previewCard))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Connect, Reduce Motion") {
    ConnectScreen(preview: .found(previewCard))
        .havenReduceMotion()
}
