import ConvexMobile
import Testing

@testable import Haven

/// Reads a string out of the argument dictionary, which holds an existential
/// and so cannot simply be compared.
private func string(_ args: [String: ConvexEncodable?], _ key: String) -> String? {
    guard let value = args[key] else { return nil }
    return value as? String
}

private func history(_ args: [String: ConvexEncodable?]) -> [[String: String]]? {
    guard let value = args["history"] else { return nil }
    return value as? [[String: String]]
}

@Suite("Ask arguments")
struct AskArgumentTests {
    @Test("a first question carries no history at all")
    func firstQuestion() {
        let args = AskModel.arguments(question: "  who knows databases  ", turns: [])
        #expect(string(args, "query") == "who knows databases")
        // `history` is optional on the server; sending an empty array would be
        // a turn count of zero dressed up as a conversation.
        #expect(args["history"] == nil)
    }

    @Test("a refinement sends both sides of the exchange, oldest first")
    func refinement() {
        let args = AskModel.arguments(
            question: "for a backend role",
            turns: [
                AskTurn(role: .user, text: "who should I talk to"),
                AskTurn(role: .assistant, text: "What do you need them for?"),
            ]
        )
        #expect(string(args, "query") == "for a backend role")
        #expect(
            history(args) == [
                ["role": "user", "text": "who should I talk to"],
                ["role": "assistant", "text": "What do you need them for?"],
            ]
        )
    }
}

@MainActor
@Suite("Asking")
struct AskingTests {
    private func answered(_ answer: AskAnswer) -> AskModel {
        AskModel(preview: .answered(answer))
    }

    @Test("a clarifying question is what opens the reply field")
    func clarifying() {
        let model = answered(AskAnswer(clarifyingQuestion: "What for?"))
        #expect(model.clarifyingQuestion == "What for?")
        #expect(model.canSendReply == false)
        model.reply = "   "
        #expect(model.canSendReply == false)
        model.reply = "a backend role"
        #expect(model.canSendReply)
    }

    @Test("an answer with matches has nothing to reply to")
    func matchedAnswerTakesNoReply() {
        let model = answered(
            AskAnswer(
                matches: [
                    AskMatch(
                        personId: "p1",
                        name: "Ada Lovelace",
                        company: nil,
                        role: nil,
                        cityName: nil,
                        kind: .direct,
                        why: "you wrote it"
                    )
                ]
            )
        )
        #expect(model.clarifyingQuestion == nil)
        model.reply = "anything"
        #expect(model.canSendReply == false)
    }

    @Test("clearing puts the screen back to search")
    func clearing() {
        let model = answered(AskAnswer(clarifyingQuestion: "What for?"))
        model.reply = "typed something"
        model.clear()
        #expect(model.state == .idle)
        #expect(model.reply == "")
    }

    @Test("an empty question is not worth a paid call")
    func emptyQuestionDoesNothing() async {
        let model = AskModel(preview: .idle)
        await model.ask("   \n ")
        #expect(model.state == .idle)
    }
}

@Suite("Match rendering")
struct AskMatchTests {
    private func match(company: String?, role: String?, city: String?) -> AskMatch {
        AskMatch(
            personId: "p1",
            name: "Ada",
            company: company,
            role: role,
            cityName: city,
            kind: .direct,
            why: "because"
        )
    }

    @Test("the line under the name is what places them, or nothing")
    func detailLine() {
        #expect(
            match(company: "Analytical Engines", role: "Engineer", city: "Sai Gon").detail
                == "Engineer, Analytical Engines | Sai Gon"
        )
        #expect(match(company: nil, role: nil, city: "Sai Gon").detail == "Sai Gon")
        // Nothing to place them by is a name on its own, which is honest.
        #expect(match(company: nil, role: nil, city: nil).detail == nil)
    }
}
