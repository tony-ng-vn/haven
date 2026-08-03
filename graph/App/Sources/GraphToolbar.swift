import SwiftUI

/// Chrome hoisted above the current step view (see ContentView): a rebuild tears the ready
/// view down and reconstructs it, and none of this state should go with it.
struct GraphToolbar: View {
    let model: AppModel

    @State private var pendingFrom: Date
    @State private var pendingTo: Date
    @State private var showingMergeQueue = false

    init(model: AppModel) {
        self.model = model
        // Seed from the range currently applied, falling back to the full span only when no
        // filter is active: after Apply, the pickers should keep showing what was just
        // applied, not silently reset to the full history.
        let bounds = model.displayOptions.dateRange ?? model.messageDateBounds
        _pendingFrom = State(initialValue: bounds?.lowerBound ?? Date())
        _pendingTo = State(initialValue: bounds?.upperBound ?? Date())
    }

    /// PLAN.md build order step 7: a quiet, easy-to-ignore status for the model pass. Nothing
    /// shows once idle or finished -- only while there is something to say (in progress, or
    /// the one actionable failure mode: no local Ollama server to talk to).
    private var guessingStatusText: String? {
        switch model.guessingState {
        case .idle, .finished:
            return nil
        case .running(let done, let total):
            return "Guessing names \(done)/\(total)"
        case .providerUnavailable:
            return "Model pass: Ollama not reachable (install Ollama to enable)"
        }
    }

    /// Same "quiet unless there's something to say" posture as guessingStatusText, but this
    /// one also shows on success (`.done`): a resync-and-push has no visible on-screen effect
    /// otherwise, so the one-shot confirmation is the only signal the sync actually happened.
    private var syncStatusText: String? {
        switch model.syncState {
        case .idle:
            return nil
        case .syncing:
            return "Syncing people..."
        case .done(let message):
            return "Synced: \(message)"
        case .failed(let message):
            return "Sync failed: \(message)"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            dateControls
            Divider().frame(height: 20)
            deadGroupsToggle
            if model.displayOptions.hiddenNodeIDs.count > 0 {
                Divider().frame(height: 20)
                hiddenIndicator
            }
            if model.removedPersonCount > 0 {
                Divider().frame(height: 20)
                removedIndicator
            }
            if !model.mergeQueue.isEmpty {
                Divider().frame(height: 20)
                mergeQueueButton
            }
            if let guessingStatusText {
                Divider().frame(height: 20)
                Text(guessingStatusText).foregroundStyle(.secondary)
            }
            if let syncStatusText {
                Divider().frame(height: 20)
                Text(syncStatusText).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Hidden entirely, not just disabled, when polygres is not installed at its known
            // path: a button that can only ever fail on this machine is worse than no button.
            if model.isPolygresAvailable {
                Button("Sync people") {
                    model.syncPeople()
                }
                .disabled(model.syncState == .syncing)
                Divider().frame(height: 20)
            }
            Button("Resync") {
                model.resync()
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .padding(14)
    }

    @ViewBuilder
    private var dateControls: some View {
        if let bounds = model.messageDateBounds {
            DatePicker("From", selection: $pendingFrom, in: bounds, displayedComponents: .date)
                .labelsHidden()
            Text("to").foregroundStyle(.secondary)
            DatePicker("To", selection: $pendingTo, in: bounds, displayedComponents: .date)
                .labelsHidden()
            Button("Apply") {
                model.setDateRange(pendingFrom...pendingTo)
            }
            if model.displayOptions.dateRange != nil {
                Button("All History") {
                    model.setDateRange(nil)
                    pendingFrom = bounds.lowerBound
                    pendingTo = bounds.upperBound
                }
            }
        } else {
            // No messages at all in the extracted history: nothing to filter, so the date
            // controls have nothing meaningful to show rather than a disabled empty range.
            Text("No message history to filter")
                .foregroundStyle(.secondary)
        }
    }

    private var deadGroupsToggle: some View {
        Toggle(
            "Show dead groups",
            isOn: Binding(
                get: { model.displayOptions.showDeadGroups },
                set: { model.setShowDeadGroups($0) }
            )
        )
        .toggleStyle(.checkbox)
    }

    private var hiddenIndicator: some View {
        HStack(spacing: 8) {
            Text("Hidden: \(model.displayOptions.hiddenNodeIDs.count)")
            Button("Unhide All") {
                model.unhideAll()
            }
        }
    }

    private var removedIndicator: some View {
        HStack(spacing: 8) {
            Text("Removed: \(model.removedPersonCount)")
            Button("Restore All") {
                model.restoreAllRemoved()
            }
        }
    }

    private var mergeQueueButton: some View {
        Button("Merge questions: \(model.mergeQueue.count)") {
            showingMergeQueue = true
        }
        .popover(isPresented: $showingMergeQueue) {
            MergeQueueView(model: model)
        }
    }
}
