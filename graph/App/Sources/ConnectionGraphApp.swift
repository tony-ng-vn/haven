import SwiftUI

@main
struct ConnectionGraphApp: App {
    var body: some Scene {
        Window("Your Sky", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1200, height: 900)
    }
}

private struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                stepView(size: proxy.size)
                // Toolbar chrome, hoisted above whatever stepView is currently showing: a
                // rebuild's brief `.loading` flash must not make the toolbar (and the Focus
                // chip / date range it holds) flicker away and back. Only relevant once
                // onboarding has actually reached the sky -- during Welcome/Authorize/
                // readyToMap/mapping there is no graph yet for it to describe.
                if model.onboardingStep == .sky, model.messageDateBounds != nil {
                    GraphToolbar(model: model)
                }
            }
            // Fires once, on first appearance. Deliberately does NOT eagerly load on
            // Welcome/Authorize/readyToMap -- reading chat.db before the user has ever
            // seen Authorize would read real data before there was any explicit consent
            // step. It only kicks off a (background, non-forced) load when a relaunch has
            // already landed straight on `.sky` -- proof access was granted in a past
            // session -- so the toolbar and the native-view toggle have something to show.
            // On a same-session walk through onboarding, startMapping()'s own forced load
            // already did this, and hasStartedLoading makes this call a harmless no-op.
            .task {
                if model.onboardingStep == .sky {
                    model.load(windowSize: proxy.size)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    @ViewBuilder
    private func stepView(size: CGSize) -> some View {
        switch model.onboardingStep {
        case .welcome:
            WelcomeView(onContinue: model.continueFromWelcome)
        case .authorize:
            AuthorizeView(model: model)
        case .readyToMap:
            ReadyToMapView(model: model, windowSize: size)
        case .mapping:
            MappingView(model: model)
        case .sky:
            skyOrNativeView(size: size)
        }
    }

    @ViewBuilder
    private func skyOrNativeView(size: CGSize) -> some View {
        if model.showNativeGraphView {
            nativeStateView(size: size)
        } else if let skyHTMLURL = model.skyHTMLURL, FileManager.default.fileExists(atPath: skyHTMLURL.path) {
            SkyView(fileURL: skyHTMLURL)
        } else {
            // onboardingStep only ever reaches `.sky` once a build actually succeeded, or a
            // relaunch confirmed the file still exists -- this should not happen, but a
            // missing file here should fall back to the native pipeline view rather than a
            // blank window.
            nativeStateView(size: size)
        }
    }

    @ViewBuilder
    private func nativeStateView(size: CGSize) -> some View {
        switch model.state {
        case .loading:
            loadingView
        case .needsPermission(let explanation):
            PermissionView(explanation: explanation) {
                model.load(windowSize: size, force: true)
            }
        case .ready(let graph, let simulation):
            GraphView(model: model, graph: graph, simulation: simulation)
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var loadingView: some View {
        ProgressView("Reading your message history...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .tint(.white)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Text("Something went wrong")
                .font(.title2)
                .bold()
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
