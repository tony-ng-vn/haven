/// Canonical, order-independent string key for an unordered pair of person ids. Shared between
/// GraphBuilder (which sees an interaction's actor/target in whatever order chat.db happened to
/// give them) and AcquaintanceDerivation (whose own roster loop already iterates in sorted
/// order) -- both sides format the key the same way, so a lookup built by one and read by the
/// other always agrees, without either owning the other's internals.
enum PersonPairKey {
    static func make(_ personA: String, _ personB: String) -> String {
        personA < personB ? "\(personA)|\(personB)" : "\(personB)|\(personA)"
    }
}
