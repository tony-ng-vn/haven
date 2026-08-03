import Foundation

/// Enforces "two distinct handles must not carry the same guessed name" as a final,
/// order-independent correction over the whole cache.
///
/// Distinct phone numbers are distinct people by construction in this project, so two of them
/// ending up with the identical guessed name is definitionally a misattribution of at least one
/// -- the model has no way to prove which one (if either) is actually correct, and grounding
/// (see GuessGrounding, the #206 fix) only proves the name's words appear somewhere in the
/// snippets, not that they are evidence about THIS specific candidate rather than a third party
/// mentioned in conversation. Measured on the real database: the same name independently passed
/// grounding for 16 different, otherwise-unrelated one-to-one threads that share no chat and no
/// group in common, purely because the underlying word/name is common enough to turn up by
/// coincidence across many separate conversations (see the guess-attribution PR for the
/// measurement). Grounding cannot see that; only comparing across the whole candidate pool can.
///
/// Deliberately "drop every member of a colliding cluster", not "keep the best one": nothing in
/// a NameGuess distinguishes a correct guess from a misattributed one once both have already
/// passed grounding, so picking a "winner" would just be a second unjustified guess. A legitimate
/// case exists too -- two real different people can genuinely share a name -- but the model
/// cannot tell that apart from a mistake, so the conservative answer (an unnamed number over a
/// possibly-misattributed identity) is applied uniformly, per the same trade #206 already made.
///
/// A pure function over the full final map, not woven into GuessEngine's per-candidate loop: it
/// needs to see every candidate's outcome at once to be order-independent, and it needs to catch
/// a collision already sitting in the cache from before this rule existed, not just ones
/// introduced by the current pass. Scoped to PERSON guesses only ("group:"-prefixed keys are
/// left untouched): a group is not "a distinct handle", and two groups (or a group and a person)
/// sharing a display name is not the mistake this rule guards against.
public enum GuessAttribution {
    public static func resolvingDuplicatePersonNames(
        in nameGuesses: [String: NameGuess]
    ) -> (resolved: [String: NameGuess], droppedKeys: Set<String>) {
        var keysByNormalizedName: [String: [String]] = [:]
        for (key, guess) in nameGuesses where !key.hasPrefix("group:") {
            keysByNormalizedName[normalize(guess.name), default: []].append(key)
        }

        let collidingKeys = Set(keysByNormalizedName.values.filter { $0.count > 1 }.flatMap { $0 })
        guard !collidingKeys.isEmpty else {
            return (nameGuesses, [])
        }

        var resolved = nameGuesses
        for key in collidingKeys {
            resolved.removeValue(forKey: key)
        }
        return (resolved, collidingKeys)
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
