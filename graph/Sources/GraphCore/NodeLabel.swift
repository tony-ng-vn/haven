import Foundation

/// The single rule for what text (if any) a node's label shows, shared by every caller that
/// turns a node into display text (GraphJSON's sky export, the CLI's `json`/`guess`
/// subcommands) so none of them can disagree: a real name always wins; a cached model guess
/// is shown tilde-prefixed, PLAN.md's "always visibly marked as a guess" signal; otherwise
/// nil, and each caller decides its own fallback.
public enum NodeLabel {
    public static func resolve(node: GraphNode, guesses: [String: NameGuess]) -> String? {
        if let name = node.name, !name.isEmpty {
            return name
        }
        guard let guess = guesses[guessKey(for: node)] else { return nil }
        return "~" + guess.name
    }

    /// A group's node id is "chat:<guid>" (GraphBuilder's own convention), but a group's guess
    /// cache key is "group:<guid>" (GuessCandidate's doc comment) -- a deliberately different
    /// prefix. Public, and the ONLY place this string transform is written: AppModel's
    /// candidate assembly calls this exact function to build a group candidate's key, rather
    /// than reimplementing the transform separately, so the write side (AppModel) and the read
    /// side (resolve, below) cannot drift apart from each other.
    public static func groupGuessKey(forNodeID nodeID: String) -> String {
        guard nodeID.hasPrefix("chat:") else { return nodeID }
        return "group:" + nodeID.dropFirst("chat:".count)
    }

    /// A person's guess key is their node id directly (the same normalized identifier
    /// GuessCandidate uses).
    private static func guessKey(for node: GraphNode) -> String {
        guard node.kind == .group else { return node.id }
        return groupGuessKey(forNodeID: node.id)
    }
}
