import SwiftUI

@main
struct ConnectionGraphApp: App {
    var body: some Scene {
        Window("ConnectionGraph", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1200, height: 900)
    }
}

private struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        GeometryReader { proxy in
            stateView(size: proxy.size)
                // Meant to fire once, on first appearance. Not verified against a real launch
                // (which this task is not allowed to do): AppModel.load's own
                // hasStartedLoading guard is what actually makes a re-fire here harmless,
                // not an assumption about this view's identity across state changes.
                .task {
                    model.load(windowSize: proxy.size)
                }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    @ViewBuilder
    private func stateView(size: CGSize) -> some View {
        switch model.state {
        case .loading:
            loadingView
        case .needsPermission(let explanation):
            PermissionView(explanation: explanation) {
                model.load(windowSize: size, force: true)
            }
        case .ready(let graph, let simulation):
            GraphView(graph: graph, simulation: simulation)
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
