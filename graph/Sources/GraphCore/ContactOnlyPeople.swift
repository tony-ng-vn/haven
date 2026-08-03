import Foundation

/// A saved contact with zero message evidence anywhere in chat.db: PLAN.md 2026-08-03, the
/// owner's reversal of the original "no nodes for people never contacted" line. Distinct from
/// Person -- a Person always has at least one handleRowID (only handles create a Person); this
/// never does, by construction (see ContactOnlyPeople.derive's own doc comment for exactly how
/// "no message evidence" is decided).
public struct ContactOnlyPerson: Sendable, Equatable {
    /// The card's own smallest normalized phone/email, matching Person.id's own convention
    /// (never a database row id) -- or, for a card with neither, "contact:<uniqueID>":
    /// ContactRecord.uniqueID is stable across resyncs (its own doc comment), which is exactly
    /// the id contract the overrides store already relies on for Person.
    public let id: String
    public let name: String
    public let thumbnailImageData: Data?
    /// ContactRecord.uniqueID, never recordID -- same reasoning as Person.contactCardIDs.
    public let contactCardID: String

    public init(id: String, name: String, thumbnailImageData: Data?, contactCardID: String) {
        self.id = id
        self.name = name
        self.thumbnailImageData = thumbnailImageData
        self.contactCardID = contactCardID
    }
}

/// The first rule (in order) that kept a contact card from becoming a node. Mirrors
/// PersonFilter.RemovalReason's own "one reason, in rule order" posture.
public enum ContactOnlyExclusionReason: Sendable, Equatable, CaseIterable {
    /// At least one of the card's own phone/email identifiers already has message evidence
    /// (PLAN.md's correctness crux): this card is not contact-only, it is already a Person.
    case matchesExistingPerson
    /// No first/last name and no nickname -- IdentityResolution.humanName is nil. Catches a
    /// business, a service, an ICE entry, or any card whose only identity signal is an
    /// organization field or nothing at all (PLAN.md's non-person examples).
    case noHumanName
    /// Every identifier is a 4-6 digit shortcode -- reuses PersonFilter's own predicate
    /// (identifiersLookLikeShortcodesOnly) rather than a second copy of the same rule.
    case shortcode
    /// Every identifier is alphanumeric (a sender id, never dialable) -- same reuse as above.
    case alphanumericSender
    /// A different, already-accepted contact-only card landed on the exact same id (a shared
    /// phone/email across two separate saved cards) -- kept once, deterministically, rather
    /// than emitting two nodes with colliding ids.
    case duplicateWithinContactOnly
}

public struct ExcludedContactCard: Sendable, Equatable {
    public let contactCardID: String
    public let reason: ContactOnlyExclusionReason

    public init(contactCardID: String, reason: ContactOnlyExclusionReason) {
        self.contactCardID = contactCardID
        self.reason = reason
    }
}

public struct ContactOnlyDerivationResult: Sendable, Equatable {
    public let people: [ContactOnlyPerson]
    public let excluded: [ExcludedContactCard]

    public init(people: [ContactOnlyPerson], excluded: [ExcludedContactCard]) {
        self.people = people
        self.excluded = excluded
    }
}

/// Derives contact-only nodes: additive to the message-based pipeline (extraction, identity
/// resolution, PersonFilter, GraphBuilder, the acquaintance layer) rather than woven into it.
/// Nothing here ever touches keptPeople, GraphBuilder, or GuessCandidateSelection -- the whole
/// point is that contact-only people cannot leak into any inference by construction, not just
/// by convention (PLAN.md 2026-08-03's exclusion requirement). Callers merge the result's
/// `people` into a Graph's nodes only at the last mile, right before GraphJSON.encode.
public enum ContactOnlyPeople {
    /// `matchedIdentifiers` MUST be built from the FULL, time-unfiltered set of chat.db handles
    /// (every RawHandle.identifier ever seen, normalized) -- never a time-windowed extract. A
    /// caller that filtered to a date range first and passed only the surviving handles would
    /// make "no message evidence" mean "no message evidence in this window", so scrubbing the
    /// time-travel slider would manufacture contact-only nodes out of people who plainly are
    /// not: absence of messages in a window is not absence of evidence.
    ///
    /// Matching is per-card: a card matches (and is skipped -- it already has a node, never a
    /// second one) the moment ANY one of its own phone/email identifiers normalizes to
    /// something in `matchedIdentifiers`. That is the exact collision case PLAN.md calls out:
    /// several numbers on one card, only one with message evidence, still one person. This
    /// does NOT chain transitively through a second, different card that happens to share an
    /// identifier with this one and does have message evidence -- that chaining is
    /// IdentityResolution.resolve's own job for someone who already has a handle, and
    /// replaying it here would mean re-deriving the full (already time-window-safe) Person
    /// list, defeating the point of this being a cheap, separate, additive pass. The gap this
    /// leaves is narrow and one-sided (at most one extra duplicate node, never a wrong merge)
    /// -- exactly the direction PLAN.md's own identity posture already prefers ("a wrong
    /// non-merge costs one duplicate node... err toward not merging").
    ///
    /// Iterates contacts sorted by uniqueID so every tie -- two cards landing on the same id,
    /// or two rows disagreeing about something -- resolves the exact same way on every run,
    /// never depending on the caller's own array order or a dictionary's iteration order.
    public static func derive(
        contacts: [ContactRecord],
        matchedIdentifiers: Set<String>
    ) -> ContactOnlyDerivationResult {
        var peopleByID: [String: ContactOnlyPerson] = [:]
        var excluded: [ExcludedContactCard] = []

        for record in contacts.sorted(by: { $0.uniqueID < $1.uniqueID }) {
            let cardIdentifiers = (record.phoneNumbers + record.emails)
                .map { HandleNormalization.normalize($0).normalizedString }

            if cardIdentifiers.contains(where: matchedIdentifiers.contains) {
                excluded.append(ExcludedContactCard(contactCardID: record.uniqueID, reason: .matchesExistingPerson))
                continue
            }
            guard let name = IdentityResolution.humanName(record) else {
                excluded.append(ExcludedContactCard(contactCardID: record.uniqueID, reason: .noHumanName))
                continue
            }
            if PersonFilter.identifiersLookLikeShortcodesOnly(cardIdentifiers) {
                excluded.append(ExcludedContactCard(contactCardID: record.uniqueID, reason: .shortcode))
                continue
            }
            if PersonFilter.identifiersLookLikeAlphanumericSenderOnly(cardIdentifiers) {
                excluded.append(ExcludedContactCard(contactCardID: record.uniqueID, reason: .alphanumericSender))
                continue
            }

            let id = cardIdentifiers.min() ?? "contact:\(record.uniqueID)"
            guard peopleByID[id] == nil else {
                excluded.append(ExcludedContactCard(contactCardID: record.uniqueID, reason: .duplicateWithinContactOnly))
                continue
            }
            peopleByID[id] = ContactOnlyPerson(
                id: id,
                name: name,
                thumbnailImageData: record.thumbnailImageData,
                contactCardID: record.uniqueID
            )
        }

        return ContactOnlyDerivationResult(
            people: peopleByID.values.sorted { $0.id < $1.id },
            excluded: excluded.sorted { $0.contactCardID < $1.contactCardID }
        )
    }

    /// The one place a ContactOnlyPerson becomes a GraphNode -- graph-cli's `json` subcommand
    /// and AppModel's sky export both merge this straight into a built Graph's `nodes` array,
    /// right before GraphJSON.encode, so this is written once rather than twice. hasContactCard
    /// is always true (a contact-only node's only reason to exist is a contact card); degree is
    /// always 0 (contact-only nodes never gain an edge, by construction); isLive and both
    /// message-date fields stay at their neutral default -- none of those describe someone with
    /// no message evidence at all.
    public static func asGraphNodes(_ people: [ContactOnlyPerson]) -> [GraphNode] {
        people.map { person in
            GraphNode(
                id: person.id,
                kind: .person,
                name: person.name,
                thumbnailImageData: person.thumbnailImageData,
                hasContactCard: true,
                isLive: false,
                degree: 0,
                hasNoMessageEvidence: true
            )
        }
    }

    /// Every normalized identifier that has EVER appeared as a message handle, from the full,
    /// time-unfiltered extract -- the "has message evidence" set `derive` requires. Never pass
    /// a time-windowed extract's handles here: a caller that filtered to a date range first and
    /// passed only the surviving handles would make "no message evidence" mean "no message
    /// evidence in this window", so scrubbing a time-travel slider would manufacture
    /// contact-only nodes out of people who plainly are not (see `derive`'s own doc comment).
    public static func messageHandleIdentifiers(_ extract: ChatExtract) -> Set<String> {
        Set(extract.handles.map { HandleNormalization.normalize($0.identifier).normalizedString })
    }
}
