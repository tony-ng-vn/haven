import Foundation

/// A live probe, not a permission-API guess: whether chat.db can actually be opened
/// read-only right now. macOS has no Messages-specific TCC prompt to query here -- Full
/// Disk Access either lets sqlite3_open_v2 succeed or it does not, so attempting the
/// exact same open ChatDatabase itself performs is the only truthful signal there is.
public enum MessagesAccessProbe {
    /// True only on a clean open. Any failure (missing file, denied access, a locked or
    /// corrupt database) reads as "not granted" here -- Authorize only needs a yes/no,
    /// the richer error detail is what ChatDatabase.extract's own failure path is for.
    public static func check(path: String) -> Bool {
        (try? SQLiteReadOnlyConnection(path: path)) != nil
    }
}

/// Same live-open discipline as MessagesAccessProbe, but three-valued: an address book
/// that was never found is not a blocked grant, it is nothing to check (see
/// ContactsPathDiscovery's own doc comment -- Contacts is an enrichment, not a
/// requirement for the graph itself).
public enum ContactsAccessProbe {
    public static func check(paths: [String]) -> ContactsAccessState {
        guard !paths.isEmpty else { return .noData }
        // Any one openable database is enough to enrich with; a linked account's store
        // being unreadable while the primary one opens fine is not worth blocking on.
        for path in paths where (try? SQLiteReadOnlyConnection(path: path)) != nil {
            return .granted
        }
        return .blocked
    }
}

/// Where to look for the user's local Contacts data. Moved out of AppModel (which used
/// to own this as a private static) so it is unit-testable without launching the app --
/// AuthorizeView's Contacts check and AppModel's real extraction now both call this one
/// implementation instead of two copies drifting apart.
public enum ContactsPathDiscovery {
    /// The real Contacts store is not one database: a top-level AddressBook-v22.abcddb
    /// plus one more per linked account under Sources/<id>/ (found the hard way, in pass
    /// 1's build-order step 2 -- see JOURNAL.md). Missing directories are not an error
    /// here, just an empty result.
    public static func discoverPaths(home: String, fileManager: FileManager = .default) -> [String] {
        let addressBookRoot = home + "/Library/Application Support/AddressBook"
        var paths: [String] = []

        let topLevelPath = addressBookRoot + "/AddressBook-v22.abcddb"
        if fileManager.fileExists(atPath: topLevelPath) {
            paths.append(topLevelPath)
        }

        let sourcesDirectory = addressBookRoot + "/Sources"
        if let entries = try? fileManager.contentsOfDirectory(atPath: sourcesDirectory) {
            for entry in entries.sorted() {
                let candidate = sourcesDirectory + "/" + entry + "/AddressBook-v22.abcddb"
                if fileManager.fileExists(atPath: candidate) {
                    paths.append(candidate)
                }
            }
        }

        return paths
    }
}
