import SwiftUI
import GraphCore

/// Onboarding step 3: the big CTA. Shown at `.readyToMap` (button state) and `.mapping`
/// (progress state) -- one view for both, since the only difference is whether mapping has
/// started yet, and splitting them would duplicate the whole visual frame for no reason.
struct ReadyToMapView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Ready to map your relationships")
                .font(.title2)
                .bold()

            Text(
                "Your Sky will read your Messages and Contacts once, right now, and build "
                    + "your sky from them. This can take a little while on a large history."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 460)

            Button("Map relationships") {
                model.startMapping()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

/// The progress screen itself, shown while `onboardingStep == .mapping`. Surfaces only what
/// AppModel's `mappingPhase` actually knows at its two real await boundaries (post-extract,
/// post-derive) -- no invented percentage bar.
struct MappingView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            Text("Mapping your relationships")
                .font(.title2)
                .bold()

            Text(phaseText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if case .failed(let message) = model.state {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var phaseText: String {
        switch model.mappingPhase {
        case .idle, .extracting:
            return "Reading your message history..."
        case .extracted(let messages, let contacts):
            return "Read \(messages) messages and \(contacts) contact cards. Building your sky..."
        case .building:
            return "Building your sky..."
        case .built(let people, let groups):
            return "Found \(people) people and \(groups) group chats. Almost there..."
        }
    }
}
