import ClerkKit
import Combine
import ConvexMobile
import SwiftUI

// Minimal Decodable for the getMyProfile result. Convex also returns _id,
// _creationTime, and updatedAt; we decode only what this probe displays.
struct MyProfile: Decodable {
    let username: String
}

// Outcome of the auth-gated profiles:getMyProfile subscription. Modeling the
// failure case explicitly is the whole point of the probe: if Clerk mints a
// token but Convex rejects it (wrong CLERK_JWT_ISSUER_DOMAIN or a misconfigured
// "convex" JWT template), requireUser throws server-side and the subscription
// fails. We must show that failure, not disguise it as an empty profile.
enum ProbeState {
    case loading
    case value(MyProfile?)  // query ran: a profile row, or nil if none yet
    case failed(String)     // subscription errored (e.g. Convex rejected the token)
}

@MainActor
final class ProfileModel: ObservableObject {
    @Published var state: ProbeState = .loading

    private var cancellable: AnyCancellable?

    init() {
        cancellable = convex
            .subscribe(to: "profiles:getMyProfile", yielding: MyProfile?.self)
            .map { ProbeState.value($0) }
            .catch { Just(ProbeState.failed(String(describing: $0))) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.state = $0 }
    }
}

struct ProfileProbeView: View {
    @StateObject private var model = ProfileModel()

    var body: some View {
        VStack(spacing: 12) {
            switch model.state {
            case .loading:
                ProgressView()
            case .value(let profile?):
                Text("Authenticated")
                    .font(.title2.bold())
                Text("Profile: @\(profile.username)")
            case .value(nil):
                Text("Authenticated")
                    .font(.title2.bold())
                Text("Signed in, query ran, no profile row yet.")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text("Convex call failed")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Sign out") {
                Task { try? await Clerk.shared.auth.signOut() }
            }
            .buttonStyle(.bordered)
        }
    }
}
