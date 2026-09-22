//
//  CouncilRunModels.swift
//  LLM Council
//

import Foundation

enum CouncilMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case compare
    case council
    case thoroughCouncil
    case rigorousCouncil

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compare: "Compare"
        case .council: "Council"
        case .thoroughCouncil: "Thorough Council"
        case .rigorousCouncil: "Rigorous Council"
        }
    }

    var isCouncil: Bool { self != .compare }
}

enum CouncilStage: String, CaseIterable, Codable, Hashable, Identifiable {
    case preparing
    case independentResponses
    case blindPeerReview
    case finalPositions
    case chairmanSynthesis
    case ratifyOrDissent
    case completed
    case failed
    case stopped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preparing: "Preparing provider sessions"
        case .independentResponses: "Round 1 — Independent Responses"
        case .blindPeerReview: "Round 2 — Blind Peer Review"
        case .finalPositions: "Round 3 — Final Positions"
        case .chairmanSynthesis: "Chairman Synthesis"
        case .ratifyOrDissent: "Ratify / Dissent"
        case .completed: "Completed"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }

    var isTerminal: Bool { self == .completed || self == .failed || self == .stopped }
}

enum CouncilTurnStatus: String, Codable, Hashable {
    case queued
    case submitting
    case waiting
    case succeeded
    case failed
    case timedOut
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .timedOut, .cancelled: true
        case .queued, .submitting, .waiting: false
        }
    }
}

struct CouncilTurn: Codable, Hashable, Identifiable {
    let id: UUID
    let stage: CouncilStage
    let providerID: ProviderID
    var prompt: String
    var responseText: String?
    var status: CouncilTurnStatus
    var attempt: Int
    var errorMessage: String?
    var startedAt: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        stage: CouncilStage,
        providerID: ProviderID,
        prompt: String,
        responseText: String? = nil,
        status: CouncilTurnStatus = .queued,
        attempt: Int = 1,
        errorMessage: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.stage = stage
        self.providerID = providerID
        self.prompt = prompt
        self.responseText = responseText
        self.status = status
        self.attempt = attempt
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

enum CouncilLogEvent: String, Codable, Hashable {
    case runCreated
    case preparationStarted
    case authenticationChecked
    case submissionStarted
    case submissionAccepted
    case completionDetected
    case responseExtracted
    case failed
    case timedOut
    case retryStarted
    case stageCompleted
    case runFailed
    case runStopped
    case runCompleted
}

struct CouncilLogEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let timestamp: Date
    let event: CouncilLogEvent
    let stage: CouncilStage?
    let providerID: ProviderID?
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        event: CouncilLogEvent,
        stage: CouncilStage? = nil,
        providerID: ProviderID? = nil,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.event = event
        self.stage = stage
        self.providerID = providerID
        self.message = message
    }
}

struct CouncilRun: Codable, Hashable, Identifiable {
    let id: UUID
    let question: String
    let mode: CouncilMode
    let participantProviderIDs: [ProviderID]
    let freshChatIsolation: Bool
    var stage: CouncilStage
    var turns: [CouncilTurn]
    var anonymityMap: [String: ProviderID]
    var logs: [CouncilLogEntry]
    var stopAfterCurrentStage: Bool
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    var chairmanProviderID: ProviderID { .chatGPT }

    var hasFailures: Bool {
        turns.contains { $0.status == .failed || $0.status == .timedOut }
    }

    init(
        id: UUID = UUID(),
        question: String,
        mode: CouncilMode,
        participantProviderIDs: [ProviderID],
        freshChatIsolation: Bool,
        stage: CouncilStage = .preparing,
        turns: [CouncilTurn] = [],
        anonymityMap: [String: ProviderID] = [:],
        logs: [CouncilLogEntry] = [],
        stopAfterCurrentStage: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        completedAt: Date? = nil
    ) throws {
        let participants = Self.unique(participantProviderIDs)
        guard mode.isCouncil else { throw CouncilRunValidationError.compareIsNotACouncilRun }
        guard participants.contains(.chatGPT) else { throw CouncilRunValidationError.chatGPTChairmanRequired }
        guard participants.count >= 2 else { throw CouncilRunValidationError.atLeastTwoProvidersRequired }
        guard Set(participants).isSubset(of: Set([.chatGPT, .claude, .gemini])) else {
            throw CouncilRunValidationError.unsupportedCouncilProvider
        }

        self.id = id
        self.question = question
        self.mode = mode
        self.participantProviderIDs = participants
        self.freshChatIsolation = freshChatIsolation
        self.stage = stage
        self.turns = turns
        self.anonymityMap = anonymityMap
        self.logs = logs
        self.stopAfterCurrentStage = stopAfterCurrentStage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    func successfulResponses(for stage: CouncilStage) -> [ProviderID: String] {
        turns.reduce(into: [ProviderID: String]()) { result, turn in
            guard turn.stage == stage,
                  turn.status == .succeeded,
                  let text = turn.responseText,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            result[turn.providerID] = text
        }
    }

    private static func unique(_ ids: [ProviderID]) -> [ProviderID] {
        var seen = Set<ProviderID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

enum CouncilRunValidationError: LocalizedError, Equatable {
    case compareIsNotACouncilRun
    case chatGPTChairmanRequired
    case atLeastTwoProvidersRequired
    case unsupportedCouncilProvider
    case emptyQuestion

    var errorDescription: String? {
        switch self {
        case .compareIsNotACouncilRun: "Choose a Council mode first."
        case .chatGPTChairmanRequired: "ChatGPT must participate because it is always Chairman."
        case .atLeastTwoProvidersRequired: "Select at least two council members."
        case .unsupportedCouncilProvider: "Council mode currently supports ChatGPT, Claude, and Gemini."
        case .emptyQuestion: "Enter a question first."
        }
    }
}

enum CouncilRunStateMachine {
    static func stages(for mode: CouncilMode) -> [CouncilStage] {
        switch mode {
        case .compare:
            []
        case .council:
            [.independentResponses, .blindPeerReview, .chairmanSynthesis]
        case .thoroughCouncil:
            [.independentResponses, .blindPeerReview, .finalPositions, .chairmanSynthesis]
        case .rigorousCouncil:
            [.independentResponses, .blindPeerReview, .finalPositions, .chairmanSynthesis, .ratifyOrDissent]
        }
    }

    static func nextStage(after stage: CouncilStage, mode: CouncilMode) -> CouncilStage? {
        let plan = stages(for: mode)
        guard let index = plan.firstIndex(of: stage) else {
            return stage == .preparing ? plan.first : nil
        }
        let next = plan.index(after: index)
        return next < plan.endIndex ? plan[next] : .completed
    }
}

struct AnonymizedCouncilResponse: Codable, Hashable, Identifiable {
    let label: String
    let providerID: ProviderID
    let text: String

    var id: String { label }
}

enum CouncilAnonymizer {
    static func anonymize(
        _ responses: [ProviderID: String],
        providerOrder: [ProviderID]? = nil
    ) -> [AnonymizedCouncilResponse] {
        let available = responses.keys.sorted { $0.rawValue < $1.rawValue }
        let requestedOrder = providerOrder ?? available.shuffled()
        let ordered = requestedOrder.filter { responses[$0] != nil }
        return ordered.enumerated().compactMap { index, providerID in
            guard let text = responses[providerID] else { return nil }
            return AnonymizedCouncilResponse(
                label: "Response \(label(for: index))",
                providerID: providerID,
                text: text
            )
        }
    }

    private static func label(for index: Int) -> String {
        let scalar = UnicodeScalar(65 + index) ?? "?"
        return String(Character(scalar))
    }
}

struct ProviderSubmissionReceipt: Sendable, Hashable {
    let providerID: ProviderID
    let baselineResponseCount: Int
    let baselineResponseText: String
    let baselineResponseFingerprints: Set<String>
    let submissionToken: String
    let submittedAt: Date
}

enum CouncilProviderClientError: LocalizedError, Equatable {
    case webViewUnavailable(ProviderID)
    case adapterUnavailable(ProviderID)
    case unauthenticated(ProviderID)
    case submissionFailed(ProviderID, String)
    case extractionFailed(ProviderID)
    case rateLimited(ProviderID, String)
    case timedOut(ProviderID)
    case freshConversationNotEmpty(ProviderID, Int)
    case recoveryFailed(ProviderID, String)

    var errorDescription: String? {
        switch self {
        case let .webViewUnavailable(provider): "\(provider.rawValue) WebView is unavailable."
        case let .adapterUnavailable(provider): "\(provider.rawValue) adapter is unavailable."
        case let .unauthenticated(provider): "\(provider.rawValue) is not signed in or its prompt is unavailable."
        case let .submissionFailed(provider, message): "\(provider.rawValue) submission failed: \(message)"
        case let .extractionFailed(provider): "Could not extract the latest \(provider.rawValue) response."
        case let .rateLimited(provider, message): "\(provider.rawValue) reported a usage limit: \(message)"
        case let .timedOut(provider): "Timed out waiting for \(provider.rawValue)."
        case let .freshConversationNotEmpty(provider, count):
            "\(provider.rawValue) did not open a fresh conversation (found \(count) existing response elements)."
        case let .recoveryFailed(provider, message): "\(provider.rawValue) recovery failed: \(message)"
        }
    }
}

@MainActor
protocol CouncilProviderClient: AnyObject {
    func submit(_ message: String, to providerID: ProviderID) async throws -> ProviderSubmissionReceipt
    func waitForCompletion(
        from receipt: ProviderSubmissionReceipt,
        timeout: TimeInterval
    ) async throws -> String
    func extractLatestResponse(from providerID: ProviderID) async throws -> String
    func startNewConversation(for providerID: ProviderID) async throws
    func isAuthenticated(_ providerID: ProviderID) async -> Bool
    func recoverFromFailure(for providerID: ProviderID) async throws
}
