import Foundation

/// What kind of node the model is being asked to name: a lone unnamed handle, or an unnamed
/// group (whose known, already-named members are the only extra context worth giving it).
public enum GuessContext: Sendable, Equatable {
    case person(identifier: String)
    case group(memberNames: [String])
}

/// Builds the plain-text instruction sent to the model. Pure string assembly: no I/O, no
/// network -- everything here is fully testable without a provider.
public enum GuessPrompt {
    public static func build(snippets: [Snippet], context: GuessContext) -> String {
        var lines: [String] = []

        switch context {
        case .person(let identifier):
            lines.append("You are looking at message snippets exchanged with an unnamed contact, identified only by \(identifier).")
        case .group(let memberNames):
            if memberNames.isEmpty {
                lines.append("You are looking at message snippets from an unnamed group chat.")
            } else {
                lines.append("You are looking at message snippets from an unnamed group chat, whose known members are: \(memberNames.joined(separator: ", ")).")
            }
        }

        lines.append("Based only on these snippets, guess a likely name and a short description of who this is.")
        lines.append("Respond with STRICT JSON only, in exactly this shape: {\"name\": string, \"description\": string}.")
        lines.append("If you cannot form a good guess, still return your best guess rather than refusing.")

        if snippets.isEmpty {
            lines.append("(No message snippets are available.)")
        } else {
            lines.append("Snippets:")
            for snippet in snippets {
                let marker = snippet.isFromMe ? "Me:" : "Them:"
                lines.append("\(marker) \(snippet.text)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
