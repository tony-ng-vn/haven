import Foundation

/// Derives person-to-person acquaintance edges from the built graph's group-chat activity
/// (PLAN.md, "The acquaintance layer"). Runs entirely over GroupChatActivity -- no database
/// read, no message text -- so it can run on every rebuild as cheaply as GraphBuilder itself.
public enum AcquaintanceDerivation {
    private struct PairKey: Hashable {
        let a: String
        let b: String
    }

    /// `fullyAcquaintedRosterKeys` must already be in CURRENT Person.id terms -- this function
    /// only ever compares it by exact set equality against `canonicalize` of a chat's live
    /// roster. A caller holding raw, possibly-stale keys as originally stored (captured at
    /// mark time, so built from whatever a member's Person.id was THEN) must translate them
    /// first via AcquaintanceRosterKey.resolve; this function does not do that translation
    /// itself, since it has no Person/identifier data to translate with, only rosters.
    public static func derive(
        groupChatActivity: [GroupChatActivity],
        fullyAcquaintedRosterKeys: Set<[String]>
    ) -> [Acquaintance] {
        // Every chat with 2+ resolved members contributes base weight to EVERY pair among its
        // roster, so a pair sharing at least one chat always gets a scoreByPair entry, even a
        // lurker pair or one that ends up below the likely floor -- the tier decision below is
        // what turns "has a score" into "appears in the export", not this accumulation step.
        var scoreByPair: [PairKey: Double] = [:]
        var evidenceByPair: [PairKey: [AcquaintanceEvidence]] = [:]
        // Every pair among a marked chat's FULL roster must promote to confirmed, including a
        // pair whose chats are otherwise all sub-threshold -- collected separately from
        // scoreByPair so marking never depends on what score happened to accumulate.
        var confirmedPairs: Set<PairKey> = []

        for chatActivity in groupChatActivity {
            let members = chatActivity.roster.sorted()
            guard members.count >= 2 else { continue } // a real group node always has 2+; defensive only
            let n = members.count
            let baseWeight = 1.0 / Double(n - 1)
            let isMarked = fullyAcquaintedRosterKeys.contains(AcquaintanceRosterKey.canonicalize(chatActivity.roster))

            for i in 0..<members.count {
                for j in (i + 1)..<members.count {
                    let personA = members[i]
                    let personB = members[j]
                    let key = PairKey(a: personA, b: personB) // members is sorted, so a < b already

                    let daysA = chatActivity.activeDaysByPersonID[personA] ?? []
                    let daysB = chatActivity.activeDaysByPersonID[personB] ?? []
                    let coActiveDays = daysA.intersection(daysB).count
                    let cappedDays = min(coActiveDays, AcquaintanceScoring.coActiveDayCapPerChat)
                    let contribution = baseWeight + Double(cappedDays) * AcquaintanceScoring.coActiveDayWeight

                    scoreByPair[key, default: 0] += contribution
                    evidenceByPair[key, default: []].append(
                        AcquaintanceEvidence(
                            chatId: chatActivity.chatId,
                            chatName: chatActivity.name,
                            memberCount: n,
                            coActiveDays: coActiveDays // raw, uncapped: a fact, not a scoring input
                        )
                    )
                    if isMarked {
                        confirmedPairs.insert(key)
                    }
                }
            }
        }

        var result: [Acquaintance] = []
        for (key, score) in scoreByPair {
            let tier: AcquaintanceTier
            if confirmedPairs.contains(key) {
                tier = .confirmed
            } else if score >= AcquaintanceScoring.strongThreshold {
                tier = .strong
            } else if score >= AcquaintanceScoring.likelyThreshold {
                tier = .likely
            } else {
                continue // below likely and never marked: no acquaintance edge recorded (PLAN.md)
            }

            let evidence = (evidenceByPair[key] ?? []).sorted { $0.chatId < $1.chatId }
            result.append(Acquaintance(a: key.a, b: key.b, tier: tier, score: score, evidence: evidence))
        }

        // scoreByPair is a Dictionary (unordered iteration); sort here so the same input always
        // yields the same output order, independent of hashing -- GraphJSON's own determinism
        // requirement depends on this, not just its own field-level sorting.
        return result.sorted { $0.a != $1.a ? $0.a < $1.a : $0.b < $1.b }
    }
}
