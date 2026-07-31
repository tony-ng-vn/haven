import SwiftUI
import GraphCore

/// Chrome hoisted above GraphView (see ContentView), not owned by it: a rebuild tears
/// GraphView down and reconstructs it, and none of this state should go with it.
struct GraphToolbar: View {
    let model: AppModel

    @State private var pendingFrom: Date
    @State private var pendingTo: Date

    init(model: AppModel) {
        self.model = model
        // Seed from the range currently applied, falling back to the full span only when no
        // filter is active: after Apply, the pickers should keep showing what was just
        // applied, not silently reset to the full history.
        let bounds = model.displayOptions.dateRange ?? model.messageDateBounds
        _pendingFrom = State(initialValue: bounds?.lowerBound ?? Date())
        _pendingTo = State(initialValue: bounds?.upperBound ?? Date())
    }

    private var focusedNodeName: String? {
        guard let id = model.focusedNodeID else { return nil }
        guard let node = model.lastReadyGraph?.nodes.first(where: { $0.id == id }) else { return id }
        return node.name ?? id
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
            if let focusedNodeName {
                Divider().frame(height: 20)
                focusChip(name: focusedNodeName)
            }
            Spacer(minLength: 0)
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

    private func focusChip(name: String) -> some View {
        HStack(spacing: 6) {
            Text("Focus: \(name)")
            Button {
                model.clearFocus()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }
}
