import Foundation

/// The load-bearing fix for the naming-hallucination bug: a model-guessed name is trustworthy
/// only if it is actually anchored in the snippet text the model was shown, not merely plausible
/// on its own. This is deliberately a pure, model-independent function -- no network, no I/O --
/// so acceptance is decided by a rule the model cannot talk its way around, and is fully testable
/// without a live provider.
public enum GuessGrounding {
    /// Below this length a token proves nothing: an isolated single letter (an initial, or just
    /// "a"/"i") turns up in almost any snippet of ordinary text, so a hallucinated one-letter
    /// "name" could otherwise pass by pure chance. Tokens shorter than this are dropped before
    /// matching rather than counted as evidence either way.
    private static let minimumSignificantTokenLength = 2

    /// Ordinary function words that are common enough in casual texting to appear in almost any
    /// conversation regardless of whether the model actually saw them as part of a name. Left
    /// uncapitalized/unfiltered, a hallucinated name built out of words like these could pass
    /// grounding by coincidence (see GuessGroundingTests for the "The Will" / "the bill will be
    /// paid" case). Keeping the list to closed-class words (articles, pronouns, prepositions,
    /// conjunctions, common auxiliaries, greetings) means it never intentionally excludes a real
    /// given name like "Grace" or "Hope" -- but a genuine "Will" or "May" cannot be grounded by
    /// that word alone. That is the accepted trade: an unnamed number beats a fabricated
    /// identity, and a second grounded token (a surname) still lets the guess through.
    private static let commonWordStopList: Set<String> = [
        "a", "an", "the",
        "i", "im", "you", "re", "he", "she", "it", "its", "we", "were", "they", "them", "their",
        "me", "my", "mine", "your", "yours", "his", "her", "hers", "our", "ours",
        "and", "or", "but", "so", "if", "of", "to", "in", "on", "at", "by", "for", "with", "from",
        "is", "am", "are", "was", "be", "been", "being",
        "will", "would", "can", "could", "may", "might", "must", "shall", "should", "do", "does", "did",
        "have", "has", "had",
        "this", "that", "these", "those", "not", "no", "yes",
        "hi", "hey", "hello", "thanks", "thank", "ok", "okay", "yeah", "yep", "sure",
    ]

    /// True only if every significant token of `name` appears, as a whole word, somewhere in
    /// `snippets` -- case-insensitively and ignoring punctuation. AND, not OR: a multi-word name
    /// where only one word is actually mentioned is not grounded (see GuessGroundingTests for
    /// why partial matches are rejected rather than accepted).
    public static func isGrounded(name: String, snippets: [Snippet]) -> Bool {
        let tokens = significantTokens(in: name)
        // Nothing left to verify -- an empty name, or a name made entirely of short/common
        // words -- is treated as unproven, never as vacuously true.
        guard !tokens.isEmpty else { return false }

        let haystack = wordSet(in: snippets.map(\.text).joined(separator: " "))
        return tokens.allSatisfy { haystack.contains($0) }
    }

    private static func significantTokens(in name: String) -> [String] {
        words(in: name).filter { $0.count >= minimumSignificantTokenLength && !commonWordStopList.contains($0) }
    }

    private static func wordSet(in text: String) -> Set<String> {
        Set(words(in: text))
    }

    /// Lowercases and splits on every non-alphanumeric character, which is what makes matching
    /// both case-insensitive and punctuation-insensitive in one pass (a comma, an apostrophe, an
    /// exclamation point are all just separators here).
    private static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
