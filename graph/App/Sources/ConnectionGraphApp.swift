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
        VStack(spacing: 0) {
            // Toolbar chrome, hoisted above whatever stepView is currently showing: a
            // rebuild's brief `.loading` flash must not make the toolbar (and the date
            // range it holds) flicker away and back. Only relevant once onboarding has
            // actually reached the sky -- during Welcome/Authorize/readyToMap/mapping
            // there is no graph yet for it to describe.
            //
            // A row in a VStack, not a ZStack overlay: template-sky.html owns the full
            // top of its own WKWebView with its own header (title, tier tabs), so
            // floating this ON TOP of the sky (the original layout) drew two headers
            // into the same space. Stacking gives the toolbar its own space and pushes
            // the sky down to start clear of it, with no coordination needed between
            // Swift and the HTML about heights.
            if model.onboardingStep == .sky, model.messageDateBounds != nil {
                GraphToolbar(model: model)
            }
            stepView
        }
        // Fires once, on first appearance. Deliberately does NOT eagerly load on
        // Welcome/Authorize/readyToMap -- reading chat.db before the user has ever
        // seen Authorize would read real data before there was any explicit consent
        // step. It only kicks off a (background, non-forced) load when a relaunch has
        // already landed straight on `.sky` -- proof access was granted in a past
        // session -- so the toolbar has something to show. On a same-session walk
        // through onboarding, startMapping()'s own forced load already did this, and
        // hasStartedLoading makes this call a harmless no-op.
        .task {
            if model.onboardingStep == .sky {
                model.load()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.onboardingStep {
        case .welcome:
            WelcomeView(onContinue: model.continueFromWelcome)
        case .authorize:
            AuthorizeView(model: model)
        case .readyToMap:
            ReadyToMapView(model: model)
        case .mapping:
            MappingView(model: model)
        case .sky:
            skyView
        }
    }

    @ViewBuilder
    private var skyView: some View {
        if let skyHTMLURL = model.skyHTMLURL, FileManager.default.fileExists(atPath: skyHTMLURL.path) {
            SkyView(fileURL: skyHTMLURL)
        } else {
            // onboardingStep only ever reaches `.sky` once a build actually succeeded, or a
            // relaunch confirmed the file still exists -- this should not happen, but there is
            // no native renderer to fall back to anymore, so surface the pipeline's own state
            // instead of a blank window.
            pipelineStateView
        }
    }

    @ViewBuilder
    private var pipelineStateView: some View {
        switch model.state {
        case .loading:
            loadingView
        case .needsPermission(let explanation):
            PermissionView(explanation: explanation) {
                model.load(force: true)
            }
        case .ready:
            failedView(message: "Your sky file could not be found. Try Resync from the toolbar, or relaunch the app.")
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
