import Foundation

/// A chat's roster (chat_handle_join) resolved to distinct KEPT/known people, per the caller's
/// own `handleToPersonID`. Every call site was computing this the same way independently --
/// ChatClassification, PersonFilter, and GraphBuilder's several roster-touching loops -- so it
/// lives here once. `handleToPersonID` is deliberately a parameter, not cached: GraphBuilder
/// passes a kept-people-only map, PersonFilter passes every identity-resolved person, and that
/// difference is load-bearing (see ChatClassification's doc comment).
public enum ChatRoster {
    public static func resolvedPersonIDs(_ chat: RawChat, handleToPersonID: [Int64: String]) -> Set<String> {
        Set(chat.memberHandleRowIDs.compactMap { handleToPersonID[$0] })
    }
}
