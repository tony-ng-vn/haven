import Foundation

/// Whether a chat renders as a direct edge to the user (`.oneToOne`) or as its own node
/// (`.group`). Shared by GraphBuilder and PersonFilter so the rule lives in exactly one
/// place: it used to be copy-pasted in both, and the two copies were both wrong the same way.
public enum ChatKind: Sendable, Equatable {
    case oneToOne
    case group
}

/// `chat_handle_join`'s roster lists only the OTHER participants -- it never includes the
/// user. Verified against the real database: every one of 1,191 style=45 (one-to-one) chats
/// has a roster of exactly 1. So a style-43 chat with a roster of "2" is not "you plus one
/// other"; it is two OTHER people, i.e. a real group. The old rule (roster row count == 2
/// means one-to-one) had this backwards, and silently discarded real group names as a result.
///
/// Classification therefore counts DISTINCT RESOLVED PEOPLE in the roster, not raw handle
/// rows: two handle rows (a phone and an email, say) can belong to one merged person, which
/// is exactly why "roster row count" ever looked like a plausible proxy in the first place.
public enum ChatClassification {
    private enum ChatStyle {
        static let oneToOne = 45
        static let group = 43
    }

    /// - roster resolves to exactly one distinct person -> one-to-one (this is also what
    ///   correctly catches the multi-service case: several of a person's own handles, still
    ///   one person, however many raw rows that is)
    /// - roster resolves to two or more distinct people -> group
    /// - roster of zero, or every handle in it unresolved -> degenerate, left unclassified
    ///
    /// The result is defined relative to `handleToPersonID`, not some absolute truth about
    /// the chat: GraphBuilder's map only contains kept people, PersonFilter's contains every
    /// identity-resolved person before filtering decides who survives. A chat can therefore
    /// classify as `.group` at PersonFilter's (pre-filter) call site and narrow to `.oneToOne`
    /// at GraphBuilder's (post-filter) call site if filtering removes all but one member of
    /// that chat -- each site is intentionally asking "as of what I already know," not
    /// "as of the full guest list."
    public static func classify(chats: [RawChat], handleToPersonID: [Int64: String]) -> [Int64: ChatKind] {
        var kinds: [Int64: ChatKind] = [:]
        for chat in chats {
            switch chat.style {
            case ChatStyle.oneToOne:
                kinds[chat.rowID] = .oneToOne
            case ChatStyle.group:
                let resolvedPeople = ChatRoster.resolvedPersonIDs(chat, handleToPersonID: handleToPersonID)
                if resolvedPeople.count == 1 {
                    kinds[chat.rowID] = .oneToOne
                } else if resolvedPeople.count >= 2 {
                    kinds[chat.rowID] = .group
                }
                // 0 resolved people: every member was removed/unresolved, or the roster
                // itself was empty. Degenerate either way, left unclassified as before.
            default:
                break
            }
        }
        return kinds
    }
}
