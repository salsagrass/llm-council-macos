//
//  CouncilCoordinator.swift
//  LLM Council
//

import Combine
import Foundation

@MainActor
final class CouncilCoordinator: ObservableObject {
    static let responseTimeout: TimeInterval = 180

    @Published private(set) var runs: [CouncilRun]
    @Published private(set) var activeRunID: UUID?
    @Published private(set) var isRunning = false
    @Published private(set) var lastErrorMessage: String?

    private let persistence: CouncilRunPersisting
    private var executionTask: Task<Void, Never>?

    init(persistence: CouncilRunPersisting? = nil) {
        self.persistence = persistence ?? FileCouncilRunPersistence()
        let restored = self.persistence.loadRuns().sorted { $0.createdAt > $1.createdAt }
        runs = restored
        activeRunID = restored.first?.id
    }

    var activeRun: CouncilRun? {
        guard let activeRunID else { return nil }
        return runs.first { $0.id == activeRunID }
    }

    func selectRun(_ runID: UUID?) {
        guard runID == nil || runs.contains(where: { $0.id == runID }) else { return }
        activeRunID = runID
        lastErrorMessage = nil
    }

    func start(
        question: String,
        mode: CouncilMode,
        participantProviderIDs: [ProviderID],
        freshChatIsolation: Bool,
        client: any CouncilProviderClient
    ) throws {
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else { throw CouncilRunValidationError.emptyQuestion }
        guard !isRunning else { return }

        var run = try CouncilRun(
            question: normalizedQuestion,
            mode: mode,
            participantProviderIDs: participantProviderIDs,
            freshChatIsolation: freshChatIsolation
        )
        run.logs.append(
            CouncilLogEntry(
                event: .runCreated,
                message: "Created \(mode.title) run with \(run.participantProviderIDs.count) participants."
            )
        )
        runs.insert(run, at: 0)
        activeRunID = run.id
        isRunning = true
        lastErrorMessage = nil
        persist()

        executionTask = Task { [weak self] in
            guard let self else { return }
            await self.executeActiveRun(client: client)
        }
    }

    func waitForCurrentRun() async {
        await executionTask?.value
    }

    func stopNow() {
        guard isRunning else { return }
        executionTask?.cancel()
        executionTask = nil
        mutateActiveRun { run in
            run.stage = .stopped
            run.completedAt = .now
            run.stopAfterCurrentStage = false
            for index in run.turns.indices where !run.turns[index].status.isTerminal {
                run.turns[index].status = .cancelled
                run.turns[index].completedAt = .now
                run.turns[index].errorMessage = "Stopped by user."
            }
            run.logs.append(CouncilLogEntry(event: .runStopped, message: "Run stopped by user."))
        }
        isRunning = false
    }

    func toggleStopAfterCurrentStage() {
        guard isRunning else { return }
        mutateActiveRun { run in
            run.stopAfterCurrentStage.toggle()
        }
    }

    func retry(turnID: UUID, client: any CouncilProviderClient) {
        guard !isRunning,
              let run = activeRun,
              let turn = run.turns.first(where: { $0.id == turnID }),
              turn.status == .failed || turn.status == .timedOut || turn.status == .cancelled
        else { return }

        isRunning = true
        lastErrorMessage = nil
        executionTask = Task { [weak self] in
            guard let self else { return }
            await self.retryTurn(turnID: turnID, client: client)
            self.isRunning = false
        }
    }

    private func executeActiveRun(client: any CouncilProviderClient) async {
        await executePreparation(client: client)
        guard !Task.isCancelled else {
            finishCancelledRunIfNeeded()
            return
        }

        if let failure = blockingFailure(after: .preparing) {
            failActiveRun(after: .preparing, message: failure)
            return
        }

        if activeRun?.stopAfterCurrentStage == true {
            mutateActiveRun { run in
                run.stage = .stopped
                run.completedAt = .now
                run.stopAfterCurrentStage = false
                run.logs.append(
                    CouncilLogEntry(
                        event: .runStopped,
                        stage: .preparing,
                        message: "Stopped after provider preparation."
                    )
                )
            }
            isRunning = false
            executionTask = nil
            return
        }

        guard let mode = activeRun?.mode else {
            isRunning = false
            return
        }

        for stage in CouncilRunStateMachine.stages(for: mode) {
            guard !Task.isCancelled else {
                finishCancelledRunIfNeeded()
                return
            }

            await execute(stage: stage, client: client)
            guard !Task.isCancelled else {
                finishCancelledRunIfNeeded()
                return
            }

            if let failure = blockingFailure(after: stage) {
                failActiveRun(after: stage, message: failure)
                return
            }

            if activeRun?.stopAfterCurrentStage == true {
                mutateActiveRun { run in
                    run.stage = .stopped
                    run.completedAt = .now
                    run.stopAfterCurrentStage = false
                    run.logs.append(
                        CouncilLogEntry(
                            event: .runStopped,
                            stage: stage,
                            message: "Stopped after \(stage.title)."
                        )
                    )
                }
                isRunning = false
                executionTask = nil
                return
            }
        }

        mutateActiveRun { run in
            run.stage = .completed
            run.completedAt = .now
            run.logs.append(CouncilLogEntry(event: .runCompleted, message: "Council run completed."))
        }
        isRunning = false
        executionTask = nil
    }

    private func executePreparation(client: any CouncilProviderClient) async {
        guard let run = activeRun else { return }
        setStage(.preparing)
        appendLog(event: .preparationStarted, stage: .preparing, message: "Preparing provider WebViews.")

        let tasks = run.participantProviderIDs.map { providerID in
            Task { @MainActor in
                do {
                    if run.freshChatIsolation {
                        try await client.startNewConversation(for: providerID)
                    }
                    let authenticated = await client.isAuthenticated(providerID)
                    guard authenticated else {
                        throw CouncilProviderClientError.unauthenticated(providerID)
                    }
                    return PreparationResult(providerID: providerID, result: .success(()))
                } catch {
                    return PreparationResult(providerID: providerID, result: .failure(error))
                }
            }
        }

        for task in tasks {
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                tasks.forEach { $0.cancel() }
            }
            guard !Task.isCancelled else {
                tasks.forEach { $0.cancel() }
                return
            }
            let prompt = run.freshChatIsolation ? "Start a fresh conversation and verify authentication." : "Verify authentication in the current conversation."
            switch result.result {
            case .success:
                upsertTurn(
                    CouncilTurn(
                        stage: .preparing,
                        providerID: result.providerID,
                        prompt: prompt,
                        responseText: "Ready",
                        status: .succeeded,
                        startedAt: .now,
                        completedAt: .now
                    )
                )
                appendLog(
                    event: .authenticationChecked,
                    stage: .preparing,
                    providerID: result.providerID,
                    message: "Provider is authenticated and ready."
                )
            case let .failure(error):
                upsertTurn(
                    CouncilTurn(
                        stage: .preparing,
                        providerID: result.providerID,
                        prompt: prompt,
                        status: status(for: error),
                        errorMessage: error.localizedDescription,
                        startedAt: .now,
                        completedAt: .now
                    )
                )
                appendFailure(error, stage: .preparing, providerID: result.providerID)
            }
        }

        appendLog(event: .stageCompleted, stage: .preparing, message: "All providers are ready or explicitly failed.")
    }

    private func execute(stage: CouncilStage, client: any CouncilProviderClient) async {
        guard let run = activeRun else { return }
        setStage(stage)

        let providers = providers(for: stage, run: run)
        let prompts = prompts(for: stage, run: run, providers: providers)
        var receipts: [(ProviderID, ProviderSubmissionReceipt)] = []

        for providerID in providers {
            guard !Task.isCancelled else { return }
            let prompt = prompts[providerID] ?? ""
            let turn = CouncilTurn(
                stage: stage,
                providerID: providerID,
                prompt: prompt,
                status: .submitting,
                startedAt: .now
            )
            upsertTurn(turn)
            appendLog(
                event: .submissionStarted,
                stage: stage,
                providerID: providerID,
                message: "Submitting stage prompt."
            )

            do {
                let receipt = try await client.submit(prompt, to: providerID)
                receipts.append((providerID, receipt))
                updateTurn(stage: stage, providerID: providerID) { turn in
                    turn.status = .waiting
                }
                appendLog(
                    event: .submissionAccepted,
                    stage: stage,
                    providerID: providerID,
                    message: "Provider accepted the prompt."
                )
            } catch {
                failTurn(stage: stage, providerID: providerID, error: error)
            }
        }

        let waitTasks = receipts.map { providerID, receipt in
            Task { @MainActor in
                do {
                    let response = try await client.waitForCompletion(
                        from: receipt,
                        timeout: Self.responseTimeout
                    )
                    return CompletionResult(providerID: providerID, result: .success(response))
                } catch {
                    return CompletionResult(providerID: providerID, result: .failure(error))
                }
            }
        }

        for task in waitTasks {
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                waitTasks.forEach { $0.cancel() }
            }
            guard !Task.isCancelled else { return }
            switch result.result {
            case let .success(response):
                updateTurn(stage: stage, providerID: result.providerID) { turn in
                    turn.status = .succeeded
                    turn.responseText = response
                    turn.errorMessage = nil
                    turn.completedAt = .now
                }
                appendLog(
                    event: .completionDetected,
                    stage: stage,
                    providerID: result.providerID,
                    message: "Streaming completed."
                )
                appendLog(
                    event: .responseExtracted,
                    stage: stage,
                    providerID: result.providerID,
                    message: "Captured \(response.count) response characters."
                )
            case let .failure(error):
                failTurn(stage: stage, providerID: result.providerID, error: error)
            }
        }

        appendLog(
            event: .stageCompleted,
            stage: stage,
            message: "All stage providers completed or explicitly failed."
        )
    }

    private func retryTurn(turnID: UUID, client: any CouncilProviderClient) async {
        guard let run = activeRun,
              let existing = run.turns.first(where: { $0.id == turnID })
        else { return }

        updateTurn(id: turnID) { turn in
            turn.status = .submitting
            turn.attempt += 1
            turn.errorMessage = nil
            turn.startedAt = .now
            turn.completedAt = nil
        }
        appendLog(
            event: .retryStarted,
            stage: existing.stage,
            providerID: existing.providerID,
            message: "Retrying failed provider turn."
        )

        do {
            if existing.stage == .preparing {
                if run.freshChatIsolation {
                    try await client.startNewConversation(for: existing.providerID)
                } else {
                    try await client.recoverFromFailure(for: existing.providerID)
                }
                guard await client.isAuthenticated(existing.providerID) else {
                    throw CouncilProviderClientError.unauthenticated(existing.providerID)
                }
                updateTurn(id: turnID) { turn in
                    turn.status = .succeeded
                    turn.responseText = "Ready"
                    turn.completedAt = .now
                }
            } else {
                try await client.recoverFromFailure(for: existing.providerID)
                let receipt = try await client.submit(existing.prompt, to: existing.providerID)
                updateTurn(id: turnID) { $0.status = .waiting }
                let response = try await client.waitForCompletion(from: receipt, timeout: Self.responseTimeout)
                updateTurn(id: turnID) { turn in
                    turn.status = .succeeded
                    turn.responseText = response
                    turn.completedAt = .now
                }
            }
        } catch {
            updateTurn(id: turnID) { turn in
                turn.status = status(for: error)
                turn.errorMessage = error.localizedDescription
                turn.completedAt = .now
            }
            appendFailure(error, stage: existing.stage, providerID: existing.providerID)
        }
    }

    private func providers(for stage: CouncilStage, run: CouncilRun) -> [ProviderID] {
        switch stage {
        case .chairmanSynthesis:
            [.chatGPT]
        case .ratifyOrDissent:
            run.participantProviderIDs.filter { $0 == .claude || $0 == .gemini }
        default:
            run.participantProviderIDs
        }
    }

    private func prompts(
        for stage: CouncilStage,
        run: CouncilRun,
        providers: [ProviderID]
    ) -> [ProviderID: String] {
        switch stage {
        case .independentResponses:
            return Dictionary(uniqueKeysWithValues: providers.map {
                ($0, CouncilPromptBuilder.independentResponse(question: run.question))
            })

        case .blindPeerReview:
            let anonymized = ensureRound1Anonymization(for: run)
            let prompt = CouncilPromptBuilder.blindPeerReview(question: run.question, responses: anonymized)
            return Dictionary(uniqueKeysWithValues: providers.map { ($0, prompt) })

        case .finalPositions:
            let originals = run.successfulResponses(for: .independentResponses)
            let reviews = anonymizedReviews(for: run)
            return Dictionary(uniqueKeysWithValues: providers.map { providerID in
                (
                    providerID,
                    CouncilPromptBuilder.finalPosition(
                        question: run.question,
                        providerID: providerID,
                        originalAnswer: originals[providerID],
                        peerReviews: reviews
                    )
                )
            })

        case .chairmanSynthesis:
            let currentRun = activeRun ?? run
            return [.chatGPT: CouncilPromptBuilder.chairmanSynthesis(run: currentRun)]

        case .ratifyOrDissent:
            let currentRun = activeRun ?? run
            let synthesis = currentRun.successfulResponses(for: .chairmanSynthesis)[.chatGPT]
                ?? "The chairman synthesis was unavailable because that turn failed."
            let prompt = CouncilPromptBuilder.ratifyOrDissent(question: run.question, synthesis: synthesis)
            return Dictionary(uniqueKeysWithValues: providers.map { ($0, prompt) })

        default:
            return [:]
        }
    }

    private func ensureRound1Anonymization(for run: CouncilRun) -> [AnonymizedCouncilResponse] {
        let responses = run.successfulResponses(for: .independentResponses)
        let anonymized = CouncilAnonymizer.anonymize(responses)
        mutateActiveRun { current in
            current.anonymityMap = Dictionary(uniqueKeysWithValues: anonymized.map { ($0.label, $0.providerID) })
        }
        return anonymized
    }

    private func anonymizedReviews(for run: CouncilRun) -> [AnonymizedCouncilResponse] {
        let reviews = run.successfulResponses(for: .blindPeerReview)
        let providerOrder = run.anonymityMap.keys.sorted().compactMap { run.anonymityMap[$0] }
        return CouncilAnonymizer.anonymize(reviews, providerOrder: providerOrder)
    }

    private func setStage(_ stage: CouncilStage) {
        mutateActiveRun { run in run.stage = stage }
    }

    private func upsertTurn(_ turn: CouncilTurn) {
        mutateActiveRun { run in
            if let index = run.turns.firstIndex(where: { $0.stage == turn.stage && $0.providerID == turn.providerID }) {
                run.turns[index] = turn
            } else {
                run.turns.append(turn)
            }
        }
    }

    private func updateTurn(
        stage: CouncilStage,
        providerID: ProviderID,
        update: (inout CouncilTurn) -> Void
    ) {
        mutateActiveRun { run in
            guard let index = run.turns.firstIndex(where: { $0.stage == stage && $0.providerID == providerID }) else {
                return
            }
            update(&run.turns[index])
        }
    }

    private func updateTurn(id: UUID, update: (inout CouncilTurn) -> Void) {
        mutateActiveRun { run in
            guard let index = run.turns.firstIndex(where: { $0.id == id }) else { return }
            update(&run.turns[index])
        }
    }

    private func failTurn(stage: CouncilStage, providerID: ProviderID, error: Error) {
        updateTurn(stage: stage, providerID: providerID) { turn in
            turn.status = status(for: error)
            turn.errorMessage = error.localizedDescription
            turn.completedAt = .now
        }
        appendFailure(error, stage: stage, providerID: providerID)
    }

    private func status(for error: Error) -> CouncilTurnStatus {
        if case CouncilProviderClientError.timedOut = error {
            return .timedOut
        }
        if error is CancellationError {
            return .cancelled
        }
        return .failed
    }

    private func appendFailure(_ error: Error, stage: CouncilStage, providerID: ProviderID) {
        appendLog(
            event: status(for: error) == .timedOut ? .timedOut : .failed,
            stage: stage,
            providerID: providerID,
            message: error.localizedDescription
        )
    }

    private func blockingFailure(after stage: CouncilStage) -> String? {
        guard let run = activeRun else { return "The active council run is unavailable." }
        let successful = run.successfulResponses(for: stage)

        switch stage {
        case .preparing:
            guard successful.count == run.participantProviderIDs.count else {
                return "Council stopped because not every selected provider opened a verified fresh, authenticated conversation."
            }
        case .independentResponses:
            guard successful.count >= 2 else {
                return "Council stopped because fewer than two independent responses were captured."
            }
        case .blindPeerReview:
            guard !successful.isEmpty else {
                return "Council stopped because no blind peer review was captured."
            }
        case .finalPositions:
            guard successful.count >= 2 else {
                return "Council stopped because fewer than two final positions were captured."
            }
        case .chairmanSynthesis:
            guard successful[.chatGPT] != nil else {
                return "Council stopped because the ChatGPT Chairman synthesis failed."
            }
        case .ratifyOrDissent:
            guard !successful.isEmpty else {
                return "Council stopped because neither ratification nor dissent was captured."
            }
        case .completed, .failed, .stopped:
            break
        }
        return nil
    }

    private func failActiveRun(after stage: CouncilStage, message: String) {
        mutateActiveRun { run in
            run.stage = .failed
            run.completedAt = .now
            run.stopAfterCurrentStage = false
            run.logs.append(CouncilLogEntry(event: .runFailed, stage: stage, message: message))
        }
        lastErrorMessage = message
        isRunning = false
        executionTask = nil
    }

    private func appendLog(
        event: CouncilLogEvent,
        stage: CouncilStage? = nil,
        providerID: ProviderID? = nil,
        message: String
    ) {
        mutateActiveRun { run in
            run.logs.append(
                CouncilLogEntry(event: event, stage: stage, providerID: providerID, message: message)
            )
        }
    }

    private func mutateActiveRun(_ update: (inout CouncilRun) -> Void) {
        guard let activeRunID,
              let index = runs.firstIndex(where: { $0.id == activeRunID })
        else { return }
        update(&runs[index])
        runs[index].updatedAt = .now
        persist()
    }

    private func finishCancelledRunIfNeeded() {
        if activeRun?.stage != .stopped {
            mutateActiveRun { run in
                run.stage = .stopped
                run.completedAt = .now
            }
        }
        isRunning = false
        executionTask = nil
    }

    private func persist() {
        persistence.saveRuns(runs)
    }
}

private struct PreparationResult {
    let providerID: ProviderID
    let result: Result<Void, Error>
}

private struct CompletionResult {
    let providerID: ProviderID
    let result: Result<String, Error>
}
