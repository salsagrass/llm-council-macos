//
//  CouncilPromptBuilder.swift
//  LLM Council
//

import Foundation

enum CouncilPromptBuilder {
    static func independentResponse(question: String) -> String {
        """
        You are participating in Round 1 of a multi-agent council. Answer the user's question independently.

        Do not identify which model or provider you are. Do not speculate about other council members, and do not assume their answers.

        USER QUESTION
        \(question)
        """
    }

    static func blindPeerReview(
        question: String,
        responses: [AnonymizedCouncilResponse]
    ) -> String {
        let responseBlock = responses.map { response in
            """
            ### \(response.label)
            \(response.text)
            """
        }.joined(separator: "\n\n")

        return """
        You are participating in Round 2 of a multi-agent council. The responses below have been randomized and anonymized. Do not guess or claim which provider wrote any response.

        USER QUESTION
        \(question)

        ANONYMIZED ROUND 1 RESPONSES
        \(responseBlock)

        Review the set critically. Your review must:
        1. identify factual or reasoning errors,
        2. identify unsupported assumptions,
        3. identify important omissions,
        4. identify the strongest reasoning in the other responses, and
        5. state what, if anything, would cause you to revise your original answer.

        Refer only to Response A, Response B, and Response C (as available). Preserve meaningful disagreement.
        """
    }

    static func finalPosition(
        question: String,
        providerID: ProviderID,
        originalAnswer: String?,
        peerReviews: [AnonymizedCouncilResponse]
    ) -> String {
        let reviewBlock = peerReviews.map { review in
            """
            ### Review from the author of \(review.label)
            \(review.text)
            """
        }.joined(separator: "\n\n")

        return """
        You are participating in Round 3 of a multi-agent council.

        USER QUESTION
        \(question)

        YOUR ORIGINAL ANSWER
        \(originalAnswer ?? "Your Round 1 answer was unavailable because that turn failed.")

        BLIND PEER-REVIEW MATERIAL
        \(reviewBlock)

        Produce your final position after considering the criticism. Do not converge merely for consensus. Preserve disagreement where warranted, correct genuine errors, and distinguish established facts from assumptions or unresolved uncertainty.

        Return a complete standalone answer. Do not mention your provider identity (internal participant: \(providerID.rawValue)).
        """
    }

    static func chairmanSynthesis(run: CouncilRun) -> String {
        let round1 = namedResponseBlock(run.successfulResponses(for: .independentResponses))
        let round2 = namedResponseBlock(run.successfulResponses(for: .blindPeerReview))
        let finalSourceStage: CouncilStage = run.mode == .council ? .independentResponses : .finalPositions
        let finalPositions = namedResponseBlock(run.successfulResponses(for: finalSourceStage))

        return """
        You are the permanent ChatGPT Chairman of a multi-agent council. Act as an impartial adjudicator and synthesizer. Do not favor ChatGPT's own answer merely because it is yours. Evaluate every position independently and preserve dissent where warranted.

        USER QUESTION
        \(run.question)

        ROUND 1 — ORIGINAL ANSWERS
        \(round1)

        ROUND 2 — PEER REVIEWS
        \(round2)

        \(run.mode == .council ? "POSITIONS USED FOR SYNTHESIS" : "ROUND 3 — FINAL POSITIONS")
        \(finalPositions)

        Produce a chairman synthesis containing:
        - areas of agreement,
        - material disagreements,
        - the strongest arguments or evidence for each unresolved position,
        - important assumptions,
        - what additional evidence would resolve uncertainty, and
        - a final synthesized answer that does not falsely imply consensus.

        Be explicit about minority or dissenting positions when they remain materially plausible.
        """
    }

    static func ratifyOrDissent(question: String, synthesis: String) -> String {
        """
        Review the ChatGPT Chairman's synthesis below against the original question and the council deliberation you participated in.

        USER QUESTION
        \(question)

        CHAIRMAN SYNTHESIS
        \(synthesis)

        Return exactly one of these forms:

        RATIFY

        or

        DISSENT: followed by the specific material factual, reasoning, omission, or representation problem.

        Do not dissent over wording alone. Do not force consensus.
        """
    }

    private static func namedResponseBlock(_ responses: [ProviderID: String]) -> String {
        if responses.isEmpty { return "No successful responses were captured for this stage." }
        return responses.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { providerID in
            guard let text = responses[providerID] else { return nil }
            let name = BuiltInProviders.byID[providerID]?.displayName ?? providerID.rawValue
            return "### \(name)\n\(text)"
        }.joined(separator: "\n\n")
    }
}
