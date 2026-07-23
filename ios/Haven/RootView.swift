import ClerkKitUI
import SwiftUI

// Phase 0 smoke test for the Clerk -> Convex authenticated seam.
// Unauthenticated: show Clerk's prebuilt AuthView (custom sign-in UI is Phase 1).
// Authenticated: call an auth-gated Convex query and render its result.
struct RootView: View {
    @StateObject private var auth = AuthModel()
    @State private var showingAuth = false

    var body: some View {
        VStack(spacing: 16) {
            switch auth.authState {
            case .loading:
                ProgressView()
            case .unauthenticated:
                Text("Haven")
                    .font(.largeTitle.bold())
                Text("Phase 0 foundations")
                    .foregroundStyle(.secondary)
                Button("Sign in") { showingAuth = true }
                    .buttonStyle(.borderedProminent)
            case .authenticated:
                ProfileProbeView()
            }
        }
        .padding()
        .sheet(isPresented: $showingAuth) {
            AuthView()
        }
    }
}

#Preview {
    RootView()
}
