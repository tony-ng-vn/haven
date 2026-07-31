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
/// one-to-one threads (style 45, plus two-member style 43 reclassified as one-to-one).
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

/// Chat style constants from the real chat.db schema (mirrors ExtractStats' private copy;
/// each file's constant is small and file-local, not worth sharing across a module boundary).
private enum ChatStyle {
    static let oneToOne = 45
    static let group = 43
}

/// How a chat is classified for filtering purposes. A two-member style-43 chat is treated
/// as one-to-one (PLAN.md: roster of exactly the user plus one other renders as a
/// one-to-one edge); anything with 0 or 1 roster members is a degenerate chat this filter
/// has no use for and is ignored.
private enum ChatKind {
    case oneToOne
    case group
}

public enum PersonFilter {
    public static func apply(
        extract: ChatExtract,
        people: [Person],
        calendar: Calendar = .current
    ) -> FilterResult {
        let chatKindByRowID = classifyChats(extract.chats)
        let handleToPersonID = Dictionary(
            uniqueKeysWithValues: people.flatMap { person in person.handleRowIDs.map { ($0, person.id) } }
        )
        let personByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })

        // Per person, the chat rowIDs (of each kind) whose roster intersects their handles.
        // Attribution is by intersection, not full roster equality: a merged, multi-service
        // person can own several one-to-one chats, each with a different single-handle
        // roster, and a two-member style-43 "user plus one other" roster only ever overlaps
        // one side's handle set anyway.
        var oneToOneChatRowIDsByPersonID: [String: Set<Int64>] = [:]
        var groupChatRowIDsByPersonID: [String: Set<Int64>] = [:]
        for chat in extract.chats {
            guard let kind = chatKindByRowID[chat.rowID] else { continue }
            let memberPersonIDs = Set(chat.memberHandleRowIDs.compactMap { handleToPersonID[$0] })
            for personID in memberPersonIDs {
                switch kind {
                case .oneToOne:
                    oneToOneChatRowIDsByPersonID[personID, default: []].insert(chat.rowID)
                case .group:
                    groupChatRowIDsByPersonID[personID, default: []].insert(chat.rowID)
                }
            }
        }

        let liveChatRowIDs = liveChats(messages: extract.messages, calendar: calendar)

        var kept: [Person] = []
        var removed: [RemovedPerson] = []

        for person in people {
            let oneToOneChatRowIDs = oneToOneChatRowIDsByPersonID[person.id] ?? []
            let groupChatRowIDs = groupChatRowIDsByPersonID[person.id] ?? []
            let oneToOneMessages = extract.messages.filter { oneToOneChatRowIDs.contains($0.chatRowID) }
            let fromMeCount = oneToOneMessages.filter(\.isFromMe).count
            let distinctActiveDays = Set(
                oneToOneMessages.map { calendar.startOfDay(for: $0.date) }
            ).count

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
                    chats: extract.chats,
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

    private static func classifyChats(_ chats: [RawChat]) -> [Int64: ChatKind] {
        var kinds: [Int64: ChatKind] = [:]
        for chat in chats {
            switch chat.style {
            case ChatStyle.oneToOne:
                kinds[chat.rowID] = .oneToOne
            case ChatStyle.group:
                if chat.memberHandleRowIDs.count == 2 {
                    kinds[chat.rowID] = .oneToOne
                } else if chat.memberHandleRowIDs.count >= 3 {
                    kinds[chat.rowID] = .group
                }
                // 0 or 1 members: a degenerate roster, not usable as either kind.
            default:
                break
            }
        }
        return kinds
    }

    /// A thread or group is live when its messages span two or more distinct calendar days,
    /// computed in the given calendar (the caller's current calendar/timezone by default).
    private static func liveChats(messages: [RawMessage], calendar: Calendar) -> Set<Int64> {
        var daysByChat: [Int64: Set<Date>] = [:]
        for message in messages {
            daysByChat[message.chatRowID, default: []].insert(calendar.startOfDay(for: message.date))
        }
        return Set(daysByChat.filter { $0.value.count >= 2 }.keys)
    }

    /// Every one of the person's identifiers is .other and is 4-6 ASCII digits.
    private static func isShortcode(_ person: Person) -> Bool {
        guard !person.identifiers.isEmpty else { return false }
        return person.identifiers.allSatisfy { identifier in
            guard case .other(let value) = HandleNormalization.normalize(identifier) else { return false }
            return (4...6).contains(value.count) && value.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// Every identifier is .other and at least one contains a letter. An email identifier
    /// already makes "every identifier is .other" false, so this can never fire for someone
    /// with an email: emails are people, no separate check needed to enforce that.
    private static func isAlphanumericSender(_ person: Person) -> Bool {
        guard !person.identifiers.isEmpty else { return false }
        let allOther = person.identifiers.allSatisfy { identifier in
            if case .other = HandleNormalization.normalize(identifier) { return true }
            return false
        }
        guard allOther else { return false }
        return person.identifiers.contains { identifier in identifier.contains { $0.isLetter } }
    }

    /// True groups only (3+ members, style 43): a shared two-member style-43 chat does not
    /// count here, per the plan's reclassification as a one-to-one edge.
    private static func sharesGroupWithContactCardPerson(
        person: Person,
        groupChatRowIDs: Set<Int64>,
        chats: [RawChat],
        handleToPersonID: [Int64: String],
        personByID: [String: Person]
    ) -> Bool {
        guard !groupChatRowIDs.isEmpty else { return false }
        let chatsByRowID = Dictionary(uniqueKeysWithValues: chats.map { ($0.rowID, $0) })
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
