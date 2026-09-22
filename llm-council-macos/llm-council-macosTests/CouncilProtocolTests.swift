//
//  CouncilProtocolTests.swift
//  LLM CouncilTests
//

import Foundation
@testable import LLM_Council
import Testing

struct CouncilProtocolTests {
    @Test("Council modes have the expected stage plans")
    func stagePlansMatchModeDepth() {
        #expect(CouncilRunStateMachine.stages(for: .compare).isEmpty)
        #expect(CouncilRunStateMachine.stages(for: .council) == [
            .independentResponses,
            .blindPeerReview,
            .chairmanSynthesis,
        ])
        #expect(CouncilRunStateMachine.stages(for: .thoroughCouncil) == [
            .independentResponses,
            .blindPeerReview,
            .finalPositions,
            .chairmanSynthesis,
        ])
        #expect(CouncilRunStateMachine.stages(for: .rigorousCouncil).last == .ratifyOrDissent)
        #expect(CouncilRunStateMachine.nextStage(after: .preparing, mode: .council) == .independentResponses)
        #expect(CouncilRunStateMachine.nextStage(after: .chairmanSynthesis, mode: .council) == .completed)
    }

    @Test("ChatGPT is enforced as the permanent chairman")
    func chairmanIsEnforced() throws {
        let valid = try CouncilRun(
            question: "Question",
            mode: .council,
            participantProviderIDs: [.claude, .chatGPT],
            freshChatIsolation: true
        )
        #expect(valid.chairmanProviderID == .chatGPT)

        var missingChairmanError: CouncilRunValidationError?
        do {
            _ = try CouncilRun(
                question: "Question",
                mode: .council,
                participantProviderIDs: [.claude, .gemini],
                freshChatIsolation: true
            )
        } catch let error as CouncilRunValidationError {
            missingChairmanError = error
        }
        #expect(missingChairmanError == .chatGPTChairmanRequired)
    }

    @Test("Round 1 responses are deterministically anonymized without provider labels")
    func anonymizationUsesOpaqueLabels() {
        let responses: [ProviderID: String] = [
            .chatGPT: "First answer",
            .claude: "Second answer",
            .gemini: "Third answer",
        ]
        let anonymized = CouncilAnonymizer.anonymize(
            responses,
            providerOrder: [.gemini, .chatGPT, .claude]
        )

        #expect(anonymized.map(\.label) == ["Response A", "Response B", "Response C"])
        #expect(anonymized.map(\.providerID) == [.gemini, .chatGPT, .claude])

        let prompt = CouncilPromptBuilder.blindPeerReview(question: "Test?", responses: anonymized)
        #expect(prompt.contains("### Response A"))
        #expect(prompt.contains("### Response B"))
        #expect(prompt.contains("### Response C"))
        #expect(!prompt.contains("ChatGPT"))
        #expect(!prompt.contains("Claude"))
        #expect(!prompt.contains("Gemini"))
    }

    @MainActor
    @Test("Rigorous council advances every stage and persists the full transcript")
    func rigorousCouncilRunsAndPersists() async throws {
        let persistence = MemoryCouncilRunPersistence()
        let client = FakeCouncilProviderClient()
        let coordinator = CouncilCoordinator(persistence: persistence)

        try coordinator.start(
            question: "Which option is strongest?",
            mode: .rigorousCouncil,
            participantProviderIDs: [.chatGPT, .claude, .gemini],
            freshChatIsolation: true,
            client: client
        )
        await coordinator.waitForCurrentRun()

        let run = try #require(coordinator.activeRun)
        #expect(run.stage == .completed)
        #expect(run.turns.count == 15)
        #expect(run.turns.allSatisfy { $0.status == .succeeded })
        #expect(run.turns.filter { $0.stage == .chairmanSynthesis }.map(\.providerID) == [.chatGPT])
        #expect(Set(run.turns.filter { $0.stage == .ratifyOrDissent }.map(\.providerID)) == Set([.claude, .gemini]))
        #expect(Set(client.startedNewConversations) == Set([.chatGPT, .claude, .gemini]))
        #expect(run.anonymityMap.count == 3)

        let restored = CouncilCoordinator(persistence: persistence)
        #expect(restored.runs.count == 1)
        #expect(restored.activeRun?.turns.count == 15)
        #expect(restored.activeRun?.question == "Which option is strongest?")
    }

    @MainActor
    @Test("A failed provider is explicit and can be retried individually")
    func failedProviderCanRetry() async throws {
        let persistence = MemoryCouncilRunPersistence()
        let client = FakeCouncilProviderClient()
        client.round1FailureBudget[.claude] = 1
        let coordinator = CouncilCoordinator(persistence: persistence)

        try coordinator.start(
            question: "Retry test",
            mode: .council,
            participantProviderIDs: [.chatGPT, .claude],
            freshChatIsolation: false,
            client: client
        )
        await coordinator.waitForCurrentRun()

        let failed = try #require(
            coordinator.activeRun?.turns.first {
                $0.stage == .independentResponses && $0.providerID == .claude
            }
        )
        #expect(failed.status == .failed)
        #expect(client.startedNewConversations.isEmpty)

        coordinator.retry(turnID: failed.id, client: client)
        await coordinator.waitForCurrentRun()

        let retried = try #require(coordinator.activeRun?.turns.first { $0.id == failed.id })
        #expect(retried.status == .succeeded)
        #expect(retried.attempt == 2)
        #expect(client.recoveredProviders.contains(.claude))
        #expect(persistence.savedRuns.first?.turns.first { $0.id == failed.id }?.status == .succeeded)
    }
}

private final class MemoryCouncilRunPersistence: CouncilRunPersisting, @unchecked Sendable {
    var savedRuns: [CouncilRun] = []

    func loadRuns() -> [CouncilRun] {
        savedRuns
    }

    func saveRuns(_ runs: [CouncilRun]) {
        savedRuns = runs
    }
}

@MainActor
private final class FakeCouncilProviderClient: CouncilProviderClient {
    var startedNewConversations: [ProviderID] = []
    var recoveredProviders: [ProviderID] = []
    var round1FailureBudget: [ProviderID: Int] = [:]

    private var nextReceiptID = 0
    private var responsesByReceiptID: [Int: String] = [:]
    private var latestResponseByProvider: [ProviderID: String] = [:]

    func submit(_ message: String, to providerID: ProviderID) async throws -> ProviderSubmissionReceipt {
        if message.contains("Round 1"), (round1FailureBudget[providerID] ?? 0) > 0 {
            round1FailureBudget[providerID, default: 0] -= 1
            throw CouncilProviderClientError.submissionFailed(providerID, "fixture failure")
        }

        nextReceiptID += 1
        let response: String
        if message.contains("RATIFY") {
            response = "RATIFY"
        } else {
            response = "\(providerID.rawValue) fixture response \(nextReceiptID)"
        }
        responsesByReceiptID[nextReceiptID] = response
        latestResponseByProvider[providerID] = response
        return ProviderSubmissionReceipt(
            providerID: providerID,
            baselineResponseCount: nextReceiptID,
            baselineResponseText: "",
            submittedAt: .now
        )
    }

    func waitForCompletion(
        from receipt: ProviderSubmissionReceipt,
        timeout _: TimeInterval
    ) async throws -> String {
        guard let response = responsesByReceiptID[receipt.baselineResponseCount] else {
            throw CouncilProviderClientError.extractionFailed(receipt.providerID)
        }
        return response
    }

    func extractLatestResponse(from providerID: ProviderID) async throws -> String {
        guard let response = latestResponseByProvider[providerID] else {
            throw CouncilProviderClientError.extractionFailed(providerID)
        }
        return response
    }

    func startNewConversation(for providerID: ProviderID) async throws {
        startedNewConversations.append(providerID)
    }

    func isAuthenticated(_: ProviderID) async -> Bool {
        true
    }

    func recoverFromFailure(for providerID: ProviderID) async throws {
        recoveredProviders.append(providerID)
    }
}
