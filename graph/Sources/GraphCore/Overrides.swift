import Foundation

/// A user's answer to one merge question: collapse the two people, or leave them separate
/// and never ask again.
public enum MergeDecision: String, Sendable, Equatable, Codable {
    case merged
    case separate
}

/// One answered merge question. identifierA/B are one normalized identifier from each side,
/// captured at answer time -- Person.id (the lexicographically smallest identifier) works for
/// this: identifiers only ever get ADDED to a person across a resync, never removed, so
/// today's Person.id remains a valid identifier of that same person forever, even after a
/// resync gives them a new, smaller one and reassigns the id. Canonicalized identifierA <
/// identifierB so a pair reads the same regardless of which side the UI happened to answer
/// from -- this canonicalization runs in this initializer, not at decode time, so it relies
/// on every MergeAnswer having been constructed through here at least once before being saved.
public struct MergeAnswer: Sendable, Equatable, Codable {
    public let identifierA: String
    public let identifierB: String
    public let decision: MergeDecision

    public init(identifierA: String, identifierB: String, decision: MergeDecision) {
        if identifierA <= identifierB {
            self.identifierA = identifierA
            self.identifierB = identifierB
        } else {
            self.identifierA = identifierB
            self.identifierB = identifierA
        }
        self.decision = decision
    }
}

/// Schema slot for the step 7 model pass cache (unnamed-handle name guessing), deliberately
/// unpopulated by this step: included here so the on-disk format is settled now rather than
/// migrated later.
public struct NameGuess: Sendable, Equatable, Codable {
    public let name: String
    public let detail: String?

    public init(name: String, detail: String? = nil) {
        self.name = name
        self.detail = detail
    }
}

/// The user's saved curation: everything that must survive a resync (PLAN.md, build order
/// step 8). Keyed throughout by normalized identifier or chat guid, never by a database row
/// id or Person.id alone -- both renumber across a resync, identifiers and guids do not.
public struct Overrides: Sendable, Equatable, Codable {
    public var hiddenPersonIdentifiers: Set<String>
    public var hiddenGroupGUIDs: Set<String>
    public var removedPersonIdentifiers: Set<String>
    public var mergeAnswers: [MergeAnswer]
    public var nameGuesses: [String: NameGuess]
    /// "Everyone here knows each other" (PLAN.md): one canonical roster key
    /// (AcquaintanceRosterKey.canonicalize) per marked group chat. Keyed by the chat's
    /// resolved member identifiers, never its guid or a row id -- see AcquaintanceRosterKey's
    /// own doc comment for why.
    public var fullyAcquaintedRosterKeys: Set<[String]>

    public init(
        hiddenPersonIdentifiers: Set<String> = [],
        hiddenGroupGUIDs: Set<String> = [],
        removedPersonIdentifiers: Set<String> = [],
        mergeAnswers: [MergeAnswer] = [],
        nameGuesses: [String: NameGuess] = [:],
        fullyAcquaintedRosterKeys: Set<[String]> = []
    ) {
        self.hiddenPersonIdentifiers = hiddenPersonIdentifiers
        self.hiddenGroupGUIDs = hiddenGroupGUIDs
        self.removedPersonIdentifiers = removedPersonIdentifiers
        self.mergeAnswers = mergeAnswers
        self.nameGuesses = nameGuesses
        self.fullyAcquaintedRosterKeys = fullyAcquaintedRosterKeys
    }

    private enum CodingKeys: String, CodingKey {
        case hiddenPersonIdentifiers, hiddenGroupGUIDs, removedPersonIdentifiers, mergeAnswers, nameGuesses
        case fullyAcquaintedRosterKeys
    }

    // Hand-written, not synthesized: every field decodes with decodeIfPresent so a file
    // written before a field existed (or a stripped-down hand edit) still loads instead of
    // throwing, and a future field can be added the same way without breaking old files.
    // Encoding is still the compiler-synthesized Encodable, generated from CodingKeys plus
    // these same stored properties.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenPersonIdentifiers = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenPersonIdentifiers) ?? []
        hiddenGroupGUIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenGroupGUIDs) ?? []
        removedPersonIdentifiers = try container.decodeIfPresent(Set<String>.self, forKey: .removedPersonIdentifiers) ?? []
        mergeAnswers = try container.decodeIfPresent([MergeAnswer].self, forKey: .mergeAnswers) ?? []
        nameGuesses = try container.decodeIfPresent([String: NameGuess].self, forKey: .nameGuesses) ?? [:]
        fullyAcquaintedRosterKeys = try container.decodeIfPresent(Set<[String]>.self, forKey: .fullyAcquaintedRosterKeys) ?? []
    }
}
