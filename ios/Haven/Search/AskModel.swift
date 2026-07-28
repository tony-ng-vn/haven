import ConvexMobile
import SwiftUI

/// One person the answer named, and why.
struct AskMatch: Decodable, Equatable, Identifiable {
    let personId: String
    let name: String
    var company: String?
    var role: String?
    var cityName: String?
    let kind: Kind
    let why: String

    var id: String { personId }

    enum Kind: String, Decodable, Equatable {
        /// This person fits the need themselves.
        case direct
        /// Nobody fits directly; this person is a likely route to someone who
        /// does. Never shown as a direct match -- the distinction is the whole
        /// feature, and flattening it would waste it.
        case bridge
    }

    /// What places them, under their name.
    var detail: String? {
        let work = [role, company].compactMap { $0 }.filter { !$0.isEmpty }
        let parts = work.isEmpty ? [] : [work.joined(separator: ", ")]
        let all = parts + [cityName].compactMap { $0 }
        return all.isEmpty ? nil : all.joined(separator: " | ")
    }
}

/// What `people:ask` returns.
struct AskAnswer: Decodable, Equatable {
    var matches: [AskMatch] = []
    /// Set instead of guessing when the request was too vague to answer.
    var clarifyingQuestion: String?
}

/// One turn of the conversation, in the shape `people:ask` takes them.
struct AskTurn: Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

enum AskState: Equatable {
    /// Nothing asked yet.
    case idle
    case thinking
    case answered(AskAnswer)
    case failed(String)
}

/// Asking Haven about the people you know.
///
/// Separate from `SearchModel` and deliberately not live: search is a free,
/// instant read that reruns as you type, and an ask is a paid call over the
/// whole network that takes seconds. Firing one on every keystroke would be
/// both slow and expensive, so this only ever runs when someone asks it to.
@MainActor
final class AskModel: ObservableObject {
    @Published private(set) var state: AskState = .idle
    /// The answer to the model's clarifying question, while one is open.
    @Published var reply = ""

    /// The conversation so far. The client owns it: `people:ask` keeps no
    /// session state, so a refinement is just another call carrying more
    /// context.
    private(set) var turns: [AskTurn] = []
    private let isLive: Bool

    init() {
        isLive = true
    }

    /// A settled state that never opens a socket, for previews and tests.
    init(preview state: AskState, turns: [AskTurn] = []) {
        isLive = false
        self.state = state
        self.turns = turns
    }

    var clarifyingQuestion: String? {
        if case .answered(let answer) = state { return answer.clarifyingQuestion }
        return nil
    }

    var canSendReply: Bool {
        clarifyingQuestion != nil && !reply.trimmed.isEmpty
    }

    /// Arguments for `people:ask`. History is only sent once there is some, so
    /// a first question carries no empty array.
    nonisolated static func arguments(
        question: String,
        turns: [AskTurn]
    ) -> [String: ConvexEncodable?] {
        var arguments: [String: ConvexEncodable?] = ["query": question.trimmed]
        if !turns.isEmpty {
            arguments["history"] = turns.map { ["role": $0.role.rawValue, "text": $0.text] }
        }
        return arguments
    }

    /// Asks a fresh question, dropping whatever was asked before.
    func ask(_ question: String) async {
        let asked = question.trimmed
        guard !asked.isEmpty else { return }
        await run(asked, after: [])
    }

    /// Answers the clarifying question, carrying both sides of the exchange
    /// forward so the model refines rather than starting over.
    func sendReply() async {
        guard let question = clarifyingQuestion, canSendReply else { return }
        let answer = reply.trimmed
        reply = ""
        // The question it asked goes in too, not just the answer: without it
        // the next call cannot tell what was being refined.
        await run(answer, after: turns + [AskTurn(role: .assistant, text: question)])
    }

    func clear() {
        state = .idle
        turns = []
        reply = ""
    }

    private func run(_ question: String, after priorTurns: [AskTurn]) async {
        state = .thinking
        let sent = AskModel.arguments(question: question, turns: priorTurns)
        guard isLive else { return }
        do {
            let answer: AskAnswer = try await convex.action("people:ask", with: sent)
            // Committed only once it lands. A question that failed was never
            // part of the conversation, and replaying it on the next call
            // would ask the model to refine something it never saw.
            turns = priorTurns + [AskTurn(role: .user, text: question)]
            state = .answered(answer)
        } catch {
            // The rate limiter and the length guards all come back as errors,
            // and none is worth its own screen -- but a silent failure on a
            // paid call is the one thing that would make this feel broken.
            state = .failed("Haven could not answer that. Try again in a moment.")
        }
    }
}
