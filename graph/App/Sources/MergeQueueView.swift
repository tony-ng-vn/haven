import SwiftUI
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
            Text("\(masked(candidate.personID1))  vs.  \(masked(candidate.personID2))")
                .font(.caption)
                .foregroundStyle(.secondary)
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
