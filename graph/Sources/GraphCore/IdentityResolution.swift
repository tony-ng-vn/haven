import Foundation

/// A resolved person: the unit the graph draws nodes for. Only handles create people
/// (PLAN.md: Contacts never creates a node); a contact card only attaches to one.
public struct Person: Sendable, Equatable {
    /// The lexicographically smallest normalized identifier in the person, never a database
    /// row id (those renumber). This is what the overrides store will key on, but note it is
    /// not fully resync-stable: attaching a new contact card can introduce a smaller phone
    /// number and shift the id (identifiers only get added, and E.164 phones sort below
    /// emails and .other values, so specifically a newly-discovered smaller phone can displace
    /// the old id). Flagging for whoever builds the overrides store on top of this.
    public let id: String
    public let identifiers: Set<String>
    public let handleRowIDs: Set<Int64>
    public let name: String?
    public let thumbnailImageData: Data?
    /// Keyed on ContactRecord.uniqueID, never recordID: the real store is three separate
    /// databases, each with its own Z_PK space, so recordID alone collides across a merged
    /// contacts list.
    public let contactCardIDs: Set<String>
    public let hasContactCard: Bool

    public init(
        id: String,
        identifiers: Set<String>,
        handleRowIDs: Set<Int64>,
        name: String?,
        thumbnailImageData: Data?,
        contactCardIDs: Set<String>,
        hasContactCard: Bool
    ) {
        self.id = id
        self.identifiers = identifiers
        self.handleRowIDs = handleRowIDs
        self.name = name
        self.thumbnailImageData = thumbnailImageData
        self.contactCardIDs = contactCardIDs
        self.hasContactCard = hasContactCard
    }
}

/// Two people whose card-derived names match but who share no identifier and no card:
/// queued for a human decision, never auto-merged.
public struct MergeCandidate: Sendable, Equatable {
    public let personID1: String
    public let personID2: String
    public let sharedName: String

    public init(personID1: String, personID2: String, sharedName: String) {
        self.personID1 = personID1
        self.personID2 = personID2
        self.sharedName = sharedName
    }
}

public struct IdentityResolutionResult: Sendable, Equatable {
    public let people: [Person]
    public let mergeCandidates: [MergeCandidate]

    public init(people: [Person], mergeCandidates: [MergeCandidate]) {
        self.people = people
        self.mergeCandidates = mergeCandidates
    }
}

public enum IdentityResolution {
    public static func resolve(
        handles: [RawHandle],
        contacts: [ContactRecord],
        assertedMerges: [(String, String)] = []
    ) -> IdentityResolutionResult {
        var unionFind = UnionFind()

        // Seed every handle's normalized identifier. Rule 1 (two handles that normalize to
        // the same string are the same person) falls out for free here: equal strings are
        // already the same union-find node, no explicit union call needed.
        var normalizedByHandleRowID: [Int64: String] = [:]
        for handle in handles {
            let normalized = HandleNormalization.normalize(handle.identifier).normalizedString
            normalizedByHandleRowID[handle.rowID] = normalized
            unionFind.makeSet(normalized)
        }

        // Rule 2: identifiers co-listed on one contact card are the same person. Card phone
        // numbers get the same normalization as handles, or co-listing never chains through.
        // Keyed on uniqueID, never recordID: the real store is three separate databases,
        // each with its own Z_PK space, and the CLI concatenates their records, so recordID
        // alone is not safe to key a merged contacts list on (it collides across dbs).
        var normalizedCardIdentifiersByCardID: [String: [String]] = [:]
        for record in contacts {
            let cardIdentifiers =
                record.phoneNumbers.map { HandleNormalization.normalize($0).normalizedString }
                    + record.emails.map { HandleNormalization.normalize($0).normalizedString }
            guard !cardIdentifiers.isEmpty else { continue }
            normalizedCardIdentifiersByCardID[record.uniqueID] = cardIdentifiers

            for identifier in cardIdentifiers {
                unionFind.makeSet(identifier)
            }
            for identifier in cardIdentifiers.dropFirst() {
                unionFind.union(cardIdentifiers[0], identifier)
            }
        }

        // Step 8: user-asserted merges (an answered merge question with decision .merged),
        // applied as extra unions on top of the automatic rules above, using the same
        // normalized strings the rest of this function already works in. union()'s own find()
        // calls makeSet() first, so an identifier neither side above has ever seen (e.g. a
        // stale answer from a resync where that side's handle disappeared) is harmless: it
        // just becomes an orphan root with no handle behind it, same as any other identifier
        // that never appears in normalizedByHandleRowID below.
        for (identifierA, identifierB) in assertedMerges {
            unionFind.union(identifierA, identifierB)
        }

        // Only handles create people (Contacts never creates a node): group handle rowIDs
        // by their union-find root, one Person per group.
        var handleRowIDsByRoot: [String: Set<Int64>] = [:]
        var identifiersByRoot: [String: Set<String>] = [:]
        for (rowID, normalized) in normalizedByHandleRowID {
            let root = unionFind.find(normalized)
            handleRowIDsByRoot[root, default: []].insert(rowID)
            identifiersByRoot[root, default: []].insert(normalized)
        }

        // A card's identifiers can extend a person's identifier set even when only one of
        // them matched a handle (e.g. an email with no handle, co-listed with a phone that
        // has one). A card whose identifiers land in no handle group attaches to nobody.
        var cardIDsByRoot: [String: Set<String>] = [:]
        for (cardID, cardIdentifiers) in normalizedCardIdentifiersByCardID {
            guard let anyIdentifier = cardIdentifiers.first else { continue }
            let root = unionFind.find(anyIdentifier)
            guard handleRowIDsByRoot[root] != nil else { continue }
            cardIDsByRoot[root, default: []].insert(cardID)
            identifiersByRoot[root, default: []].formUnion(cardIdentifiers)
        }

        // uniqueID is non-null and distinct on every ABCDContact row (measured across all
        // three real databases), so this is safe across a merged, multi-database contacts
        // list in a way keying on recordID never was.
        let contactsByCardID = Dictionary(uniqueKeysWithValues: contacts.map { ($0.uniqueID, $0) })

        var people: [Person] = []
        for (root, handleRowIDs) in handleRowIDsByRoot {
            let identifiers = identifiersByRoot[root] ?? []
            let cardIDs = (cardIDsByRoot[root] ?? []).sorted()
            let attachedRecords = cardIDs.compactMap { contactsByCardID[$0] }

            // If two cards attach to one person, prefer the card that supplied the name:
            // both the name and the photo come from that same card.
            let namingRecord = attachedRecords.first { derivedName($0) != nil }
            let photoRecord = namingRecord ?? attachedRecords.first

            // Every root here got at least one identifier inserted in the handle-grouping
            // loop above, so identifiers is never empty.
            let id = identifiers.min()!

            people.append(
                Person(
                    id: id,
                    identifiers: identifiers,
                    handleRowIDs: handleRowIDs,
                    name: namingRecord.flatMap(derivedName),
                    thumbnailImageData: photoRecord?.thumbnailImageData,
                    contactCardIDs: Set(cardIDs),
                    hasContactCard: !cardIDs.isEmpty
                )
            )
        }
        people.sort { $0.id < $1.id }

        return IdentityResolutionResult(people: people, mergeCandidates: mergeCandidates(among: people))
    }

    /// "first last" trimmed, falling back to nickname, then organization.
    private static func derivedName(_ record: ContactRecord) -> String? {
        let fullName = [record.firstName, record.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }

        if let nickname = record.nickname?.trimmingCharacters(in: .whitespaces), !nickname.isEmpty {
            return nickname
        }
        if let organization = record.organization?.trimmingCharacters(in: .whitespaces), !organization.isEmpty {
            return organization
        }
        return nil
    }

    /// Two distinct Person entries are always disjoint in identifiers and contact records
    /// by construction (they are separate union-find groups), so equal card-derived names
    /// is the only extra check a merge candidate needs.
    private static func mergeCandidates(among people: [Person]) -> [MergeCandidate] {
        var candidates: [MergeCandidate] = []
        for i in 0..<people.count {
            guard let nameI = people[i].name, !nameI.isEmpty else { continue }
            for j in (i + 1)..<people.count {
                guard let nameJ = people[j].name, !nameJ.isEmpty else { continue }
                guard nameI.caseInsensitiveCompare(nameJ) == .orderedSame else { continue }
                candidates.append(
                    MergeCandidate(personID1: people[i].id, personID2: people[j].id, sharedName: nameI)
                )
            }
        }
        candidates.sort { lhs, rhs in
            lhs.personID1 != rhs.personID1 ? lhs.personID1 < rhs.personID1 : lhs.personID2 < rhs.personID2
        }
        return candidates
    }
}

/// Dictionary-based union-find over normalized identifier strings, with path compression.
private struct UnionFind {
    private var parent: [String: String] = [:]

    mutating func makeSet(_ value: String) {
        if parent[value] == nil {
            parent[value] = value
        }
    }

    mutating func find(_ value: String) -> String {
        makeSet(value)
        if parent[value] != value {
            parent[value] = find(parent[value]!)
        }
        return parent[value]!
    }

    mutating func union(_ a: String, _ b: String) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        // Deterministic attach point; the resulting partition is order-independent either way.
        if rootA < rootB {
            parent[rootB] = rootA
        } else {
            parent[rootA] = rootB
        }
    }
}
