import Foundation

/// Chat style constants from the real chat.db schema.
private enum ChatStyle {
    static let oneToOne = 45
    static let group = 43
}

/// Roster size counts for style-43 (group) chats: min/max are nil when there are none,
/// since `.min()` on an empty collection would crash.
public struct GroupSizeDistribution: Sendable, Equatable {
    public let min: Int?
    public let max: Int?
    public let countBySize: [Int: Int]

    public init(min: Int?, max: Int?, countBySize: [Int: Int]) {
        self.min = min
        self.max = max
        self.countBySize = countBySize
    }
}

/// Pure, unit-tested instrumentation over a ChatExtract, used to tune later filters.
public struct ExtractStats: Sendable, Equatable {
    public let messageCount: Int
    public let fromMeCount: Int
    public let toMeCount: Int

    public let handleRowCount: Int
    public let distinctIdentifierCount: Int

    public let chatCount: Int
    public let oneToOneChatCount: Int
    public let groupChatCount: Int

    public let oneToOneChatsWithMessages: Int
    public let emptyOneToOneChats: Int
    public let neverRepliedOneToOneChats: Int

    public let twoMemberGroupStyleChats: Int
    public let shortcodeHandleCount: Int

    public let groupSizeDistribution: GroupSizeDistribution
    public let serviceMix: [String: Int]

    public static func compute(_ extract: ChatExtract) -> ExtractStats {
        let fromMeCount = extract.messages.filter(\.isFromMe).count
        let toMeCount = extract.messages.count - fromMeCount

        let distinctIdentifierCount = Set(extract.handles.map(\.identifier)).count

        var messageCountByChat: [Int64: Int] = [:]
        var fromMeCountByChat: [Int64: Int] = [:]
        for message in extract.messages {
            messageCountByChat[message.chatRowID, default: 0] += 1
            if message.isFromMe {
                fromMeCountByChat[message.chatRowID, default: 0] += 1
            }
        }

        var oneToOneChatsWithMessages = 0
        var emptyOneToOneChats = 0
        var neverRepliedOneToOneChats = 0
        var oneToOneChatCount = 0
        var groupChatCount = 0
        var twoMemberGroupStyleChats = 0
        var groupSizes: [Int] = []

        for chat in extract.chats {
            switch chat.style {
            case ChatStyle.oneToOne:
                oneToOneChatCount += 1
                let messageCount = messageCountByChat[chat.rowID] ?? 0
                if messageCount > 0 {
                    oneToOneChatsWithMessages += 1
                    if (fromMeCountByChat[chat.rowID] ?? 0) == 0 {
                        neverRepliedOneToOneChats += 1
                    }
                } else {
                    emptyOneToOneChats += 1
                }
            case ChatStyle.group:
                groupChatCount += 1
                let size = chat.memberHandleRowIDs.count
                groupSizes.append(size)
                if size == 2 {
                    twoMemberGroupStyleChats += 1
                }
            default:
                break
            }
        }

        let shortcodeHandleCount = extract.handles.filter { isShortcode($0.identifier) }.count

        var serviceMix: [String: Int] = [:]
        for handle in extract.handles {
            serviceMix[handle.service, default: 0] += 1
        }

        let groupSizeDistribution = GroupSizeDistribution(
            min: groupSizes.min(),
            max: groupSizes.max(),
            countBySize: Dictionary(grouping: groupSizes, by: { $0 }).mapValues(\.count)
        )

        return ExtractStats(
            messageCount: extract.messages.count,
            fromMeCount: fromMeCount,
            toMeCount: toMeCount,
            handleRowCount: extract.handles.count,
            distinctIdentifierCount: distinctIdentifierCount,
            chatCount: extract.chats.count,
            oneToOneChatCount: oneToOneChatCount,
            groupChatCount: groupChatCount,
            oneToOneChatsWithMessages: oneToOneChatsWithMessages,
            emptyOneToOneChats: emptyOneToOneChats,
            neverRepliedOneToOneChats: neverRepliedOneToOneChats,
            twoMemberGroupStyleChats: twoMemberGroupStyleChats,
            shortcodeHandleCount: shortcodeHandleCount,
            groupSizeDistribution: groupSizeDistribution,
            serviceMix: serviceMix
        )
    }

    /// A shortcode is 4 to 6 ASCII digits; any letter makes it an alphanumeric sender id instead.
    private static func isShortcode(_ identifier: String) -> Bool {
        guard (4...6).contains(identifier.count) else { return false }
        return identifier.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
