import SwiftUI
import AppKit
import GraphCore

/// The merge queue popover content: each still-open MergeCandidate (already suppressed
/// against every answered question -- see AppModel.mergeQueue) with Merge / Keep separate
/// buttons. Both sides share the same card-derived name by construction (that is exactly why
/// they are a candidate in the first place), so the two sides are told apart by a masked
/// tail of their own identifier instead of by name.
struct MergeQueueView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Merge questions").font(.headline)
            if model.mergeQueue.isEmpty {
                Text("Nothing left to answer.")
                    .foregroundStyle(.secondary)
            } else {
                // Indexed, not id: \.self: MergeCandidate is Equatable but not Hashable, and
                // adding Hashable to a GraphCore type just to satisfy this one view is not
                // worth widening that type's public conformances.
                ForEach(Array(model.mergeQueue.enumerated()), id: \.offset) { _, candidate in
                    candidateRow(candidate)
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func candidateRow(_ candidate: MergeCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.sharedName).bold()
            HStack(spacing: 4) {
                CopyableIdentifier(maskedLabel: masked(candidate.personID1), fullValue: candidate.personID1)
                Text("vs.").font(.caption).foregroundStyle(.secondary)
                CopyableIdentifier(maskedLabel: masked(candidate.personID2), fullValue: candidate.personID2)
            }
            HStack {
                Button("Merge") {
                    model.answerMerge(candidate, decision: .merged)
                }
                Button("Keep separate") {
                    model.answerMerge(candidate, decision: .separate)
                }
            }
        }
    }

    /// The last 4 characters only, so a UI element someone might glance at over the user's
    /// shoulder never shows a full phone number or email -- just enough to tell two
    /// identically-named cards apart.
    private func masked(_ identifier: String) -> String {
        guard identifier.count > 4 else { return identifier }
        return "..." + identifier.suffix(4)
    }
}

/// A masked identifier that copies its *full* value in one click. The mask above is about
/// a shoulder-surfer glancing at the screen, not about the window's own owner deliberately
/// clicking to paste the real number/handle into Messages or Contacts to tell the two
/// candidates apart -- that deliberate click is exactly what this button is for.
private struct CopyableIdentifier: View {
    let maskedLabel: String
    let fullValue: String
    @State private var justCopied = false

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(fullValue, forType: .string)
            justCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { justCopied = false }
        } label: {
            Text(justCopied ? "Copied" : maskedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        // Deliberately does not speak the digits: the label is masked on screen against a
        // shoulder-surfer, and a screen reader reading the full number aloud undoes that.
        .accessibilityLabel("Copy full number")
    }
}
