import Foundation

/// Filters merge candidates the user has already answered out of the queue (PLAN.md:
/// "answered merge questions are never re-asked"). A `separate` answer is the whole reason
/// this exists; a `merged` answer suppresses too, defensively -- the pair will usually have
/// already collapsed into one Person via IdentityResolution's assertedMerges by the time this
/// runs, leaving no candidate to suppress, but a merge answer whose identifiers only cover
/// part of either side's identifier set should still never resurface the same question.
public enum MergeCandidateSuppression {
    public static func apply(
        candidates: [MergeCandidate],
        people: [Person],
        answers: [MergeAnswer]
    ) -> [MergeCandidate] {
        guard !answers.isEmpty else { return candidates }
        let identifiersByPersonID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.identifiers) })

        return candidates.filter { candidate in
            let identifiers1 = identifiersByPersonID[candidate.personID1] ?? []
            let identifiers2 = identifiersByPersonID[candidate.personID2] ?? []
            // A candidate is suppressed when one side's identifiers contain identifierA and
            // the other's contain identifierB, in EITHER order: the answer does not know or
            // care which side of the candidate it was originally presented against.
            let isAnswered = answers.contains { answer in
                (identifiers1.contains(answer.identifierA) && identifiers2.contains(answer.identifierB))
                    || (identifiers1.contains(answer.identifierB) && identifiers2.contains(answer.identifierA))
            }
            return !isAnswered
        }
    }
}
