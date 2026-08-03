import Foundation

/// The first rule (in order) that removed a person. Only one reason per person: the plan's
/// rule order decides which fires when several would independently apply.
public enum RemovalReason: Sendable, Equatable, CaseIterable {
    case shortcode
    case alphanumericSender
    case neverReplied
    case notLive
}

/// Per-person facts a human reviewing the kill list needs, scoped to the person's combined
/// one-to-one threads (style 45, plus any style-43 chat whose roster resolves to just this
/// one person).
public struct PersonActivityFacts: Sendable, Equatable {
    public let oneToOneMessageCount: Int
    public let fromMeCount: Int
    public let distinctActiveDays: Int
    public let groupMemberships: Int

    public init(oneToOneMessageCount: Int, fromMeCount: Int, distinctActiveDays: Int, groupMemberships: Int) {
        self.oneToOneMessageCount = oneToOneMessageCount
        self.fromMeCount = fromMeCount
        self.distinctActiveDays = distinctActiveDays
        self.groupMemberships = groupMemberships
    }
}

public struct RemovedPerson: Sendable, Equatable {
    public let person: Person
    public let reason: RemovalReason
    public let facts: PersonActivityFacts

    public init(person: Person, reason: RemovalReason, facts: PersonActivityFacts) {
        self.person = person
        self.reason = reason
        self.facts = facts
    }
}

public struct FilterResult: Sendable, Equatable {
    public let kept: [Person]
    public let removed: [RemovedPerson]

    public init(kept: [Person], removed: [RemovedPerson]) {
        self.kept = kept
        self.removed = removed
    }
}

public enum PersonFilter {
    public static func apply(
        extract: ChatExtract,
        people: [Person],
        calendar: Calendar = .current
    ) -> FilterResult {
        let handleToPersonID = Dictionary(
            uniqueKeysWithValues: people.flatMap { person in person.handleRowIDs.map { ($0, person.id) } }
        )
        let chatKindByRowID = ChatClassification.classify(chats: extract.chats, handleToPersonID: handleToPersonID)
        let personByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })

        // Per person, the chat rowIDs (of each kind) whose roster intersects their handles.
        // Attribution is by intersection, not full roster equality: a merged, multi-service
        // person can own several one-to-one chats, each with a different single-handle
        // roster -- one style 45, another a style-43 roster that resolves to just them.
        var oneToOneChatRowIDsByPersonID: [String: Set<Int64>] = [:]
        var groupChatRowIDsByPersonID: [String: Set<Int64>] = [:]
        for chat in extract.chats {
            guard let kind = chatKindByRowID[chat.rowID] else { continue }
            let memberPersonIDs = ChatRoster.resolvedPersonIDs(chat, handleToPersonID: handleToPersonID)
            for personID in memberPersonIDs {
                switch kind {
                case .oneToOne:
                    oneToOneChatRowIDsByPersonID[personID, default: []].insert(chat.rowID)
                case .group:
                    groupChatRowIDsByPersonID[personID, default: []].insert(chat.rowID)
                }
            }
        }

        // Bucket messages by chat ONCE, not per person: every per-person one-to-one message
        // list below is a handful of chatRowID lookups into this map instead of a full scan
        // of extract.messages (previously O(people x messages), the dominant cost in a real
        // ~2,100-handle / ~110k-message database). liveChats reuses the same map for the same
        // reason -- it used to build an identical bucketing of its own.
        var messagesByChat: [Int64: [RawMessage]] = [:]
        for message in extract.messages {
            messagesByChat[message.chatRowID, default: []].append(message)
        }
        let liveChatRowIDs = liveChats(messagesByChat: messagesByChat, calendar: calendar)

        // Built once and reused by sharesGroupWithContactCardPerson for every person, instead
        // of that function rebuilding this same ~1,300-entry dictionary on every call.
        let chatsByRowID = Dictionary(uniqueKeysWithValues: extract.chats.map { ($0.rowID, $0) })

        var kept: [Person] = []
        var removed: [RemovedPerson] = []

        for person in people {
            let oneToOneChatRowIDs = oneToOneChatRowIDsByPersonID[person.id] ?? []
            let groupChatRowIDs = groupChatRowIDsByPersonID[person.id] ?? []
            let oneToOneMessages = oneToOneChatRowIDs.flatMap { messagesByChat[$0] ?? [] }
            let fromMeCount = oneToOneMessages.filter(\.isFromMe).count
            let distinctActiveDays = ActivityDays.distinctDays(oneToOneMessages, calendar: calendar)

            let facts = PersonActivityFacts(
                oneToOneMessageCount: oneToOneMessages.count,
                fromMeCount: fromMeCount,
                distinctActiveDays: distinctActiveDays,
                groupMemberships: groupChatRowIDs.count
            )

            var reason: RemovalReason?

            // Two positive overrides outrank rules 1-3, never rule 4: node eligibility
            // (is this worth a node at all) is a separate question from humanness.
            let overridden = person.hasContactCard
                || sharesGroupWithContactCardPerson(
                    person: person,
                    groupChatRowIDs: groupChatRowIDs,
                    chatsByRowID: chatsByRowID,
                    handleToPersonID: handleToPersonID,
                    personByID: personByID
                )

            if !overridden {
                if isShortcode(person) {
                    reason = .shortcode
                } else if isAlphanumericSender(person) {
                    reason = .alphanumericSender
                } else if facts.oneToOneMessageCount > 0 && facts.fromMeCount == 0 && facts.groupMemberships == 0 {
                    reason = .neverReplied
                }
            }

            if reason == nil {
                let isLive = oneToOneChatRowIDs.contains { liveChatRowIDs.contains($0) }
                    || groupChatRowIDs.contains { liveChatRowIDs.contains($0) }
                if !isLive {
                    reason = .notLive
                }
            }

            if let reason {
                removed.append(RemovedPerson(person: person, reason: reason, facts: facts))
            } else {
                kept.append(person)
            }
        }

        return FilterResult(kept: kept, removed: removed)
    }

    /// A thread or group is live when its messages span two or more distinct calendar days,
    /// computed in the given calendar (the caller's current calendar/timezone by default).
    private static func liveChats(messagesByChat: [Int64: [RawMessage]], calendar: Calendar) -> Set<Int64> {
        Set(
            messagesByChat
                .filter { ActivityDays.distinctDays($0.value, calendar: calendar) >= 2 }
                .keys
        )
    }

    /// Every one of the person's identifiers is .other and is 4-6 ASCII digits.
    private static func isShortcode(_ person: Person) -> Bool {
        identifiersLookLikeShortcodesOnly(person.identifiers)
    }

    /// Every identifier is .other and at least one contains a letter. An email identifier
    /// already makes "every identifier is .other" false, so this can never fire for someone
    /// with an email: emails are people, no separate check needed to enforce that.
    private static func isAlphanumericSender(_ person: Person) -> Bool {
        identifiersLookLikeAlphanumericSenderOnly(person.identifiers)
    }

    /// The identifier-only half of isShortcode, pulled out so ContactOnlyPeople.derive can
    /// apply the exact same rule to a contact card's raw phone/email strings, which never come
    /// packaged as a Person. `some Collection` rather than `Set`: PersonFilter's own callers
    /// keep passing a Person's identifier Set unchanged, and a contact card's identifiers are
    /// naturally an ordered Array (a Set here would hide a duplicate value, mildly wrong for
    /// something that is not actually a uniqueness-sensitive check). Internal, not private:
    /// ContactOnlyPeople (same module) is the other caller.
    static func identifiersLookLikeShortcodesOnly(_ identifiers: some Collection<String>) -> Bool {
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { identifier in
            guard case .other(let value) = HandleNormalization.normalize(identifier) else { return false }
            return (4...6).contains(value.count) && value.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// The identifier-only half of isAlphanumericSender -- see identifiersLookLikeShortcodesOnly
    /// just above for why this takes a plain identifier collection instead of a Person.
    static func identifiersLookLikeAlphanumericSenderOnly(_ identifiers: some Collection<String>) -> Bool {
        guard !identifiers.isEmpty else { return false }
        let allOther = identifiers.allSatisfy { identifier in
            if case .other = HandleNormalization.normalize(identifier) { return true }
            return false
        }
        guard allOther else { return false }
        return identifiers.contains { identifier in identifier.contains { $0.isLetter } }
    }

    /// True groups only (2+ distinct resolved people, style 43, per ChatClassification): a
    /// style-43 roster that resolves to just one person does not count here, since it was
    /// classified one-to-one, not a group, in the first place.
    private static func sharesGroupWithContactCardPerson(
        person: Person,
        groupChatRowIDs: Set<Int64>,
        chatsByRowID: [Int64: RawChat],
        handleToPersonID: [Int64: String],
        personByID: [String: Person]
    ) -> Bool {
        guard !groupChatRowIDs.isEmpty else { return false }
        for chatRowID in groupChatRowIDs {
            guard let chat = chatsByRowID[chatRowID] else { continue }
            for handleID in chat.memberHandleRowIDs {
                guard let otherPersonID = handleToPersonID[handleID], otherPersonID != person.id else { continue }
                if personByID[otherPersonID]?.hasContactCard == true {
                    return true
                }
            }
        }
        return false
    }
}
