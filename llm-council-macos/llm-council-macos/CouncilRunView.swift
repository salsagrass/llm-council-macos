//
//  CouncilRunView.swift
//  LLM Council
//

import AppKit
import SwiftUI

struct CouncilRunView: View {
    @ObservedObject var coordinator: CouncilCoordinator
    let mode: CouncilMode
    @Binding var selectedProviderIDs: Set<ProviderID>
    @Binding var freshChatIsolation: Bool
    let startErrorMessage: String?
    let onRetry: (UUID) -> Void

    private let councilProviders: [ProviderID] = [.chatGPT, .claude, .gemini]

    var body: some View {
        VStack(spacing: 0) {
            configurationBar
            Divider()

            if let run = coordinator.activeRun {
                runTranscript(run)
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var configurationBar: some View {
        VStack(alignment: .leading, spacing: CouncilSpacing.md) {
            HStack(spacing: CouncilSpacing.lg) {
                Text("Council members")
                    .font(CouncilTypography.detailStrong)

                ForEach(councilProviders, id: \.self) { providerID in
                    providerToggle(providerID)
                }

                Spacer()

                Toggle("Fresh conversations", isOn: $freshChatIsolation)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(coordinator.isRunning)
                    .help("Start each selected provider in a fresh conversation before Round 1.")
            }

            HStack(spacing: CouncilSpacing.md) {
                Label("ChatGPT is permanently assigned as Chairman", systemImage: "person.crop.circle.badge.checkmark")
                    .font(CouncilTypography.meta)
                    .foregroundStyle(.secondary)

                Spacer()

                if !coordinator.runs.isEmpty {
                    Menu("Past Runs") {
                        ForEach(coordinator.runs) { run in
                            Button {
                                coordinator.selectRun(run.id)
                            } label: {
                                Text("\(run.mode.title) — \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                    }
                    .controlSize(.small)

                    Button("New Run") {
                        coordinator.selectRun(nil)
                    }
                    .controlSize(.small)
                    .disabled(coordinator.isRunning)
                }
            }

            if let startErrorMessage {
                Label(startErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(CouncilTypography.meta)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, CouncilSpacing.xl)
        .padding(.vertical, CouncilSpacing.md)
        .background(.thinMaterial)
    }

    private func providerToggle(_ providerID: ProviderID) -> some View {
        let definition = BuiltInProviders.byID[providerID]
        let isChairman = providerID == .chatGPT
        return Toggle(
            definition?.displayName ?? providerID.rawValue,
            isOn: Binding(
                get: { selectedProviderIDs.contains(providerID) },
                set: { isSelected in
                    if isChairman { return }
                    if isSelected {
                        selectedProviderIDs.insert(providerID)
                    } else {
                        selectedProviderIDs.remove(providerID)
                    }
                }
            )
        )
        .toggleStyle(.checkbox)
        .disabled(isChairman || coordinator.isRunning)
        .help(isChairman ? "ChatGPT is required and always serves as Chairman." : "Include this provider in the council run.")
    }

    private var emptyState: some View {
        VStack(spacing: CouncilSpacing.xl) {
            Image(systemName: "person.3.sequence.fill")
                .font(CouncilTypography.largeIcon)
                .foregroundStyle(.tint)

            Text(mode.title)
                .font(CouncilTypography.emptyStateTitle)

            Text(modeDescription)
                .font(CouncilTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)

            if let startErrorMessage {
                Label(startErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(CouncilTypography.detail)
                    .foregroundStyle(.red)
            }

            Text("Enter the question below, then choose Start Council. Every intermediate response will appear here and be saved locally.")
                .font(CouncilTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(CouncilSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modeDescription: String {
        switch mode {
        case .compare:
            ""
        case .council:
            "Independent answers, blind peer review, and an impartial ChatGPT Chairman synthesis."
        case .thoroughCouncil:
            "Adds revised final positions before the ChatGPT Chairman evaluates the council."
        case .rigorousCouncil:
            "Adds final positions plus a Claude and Gemini ratify-or-dissent check after synthesis."
        }
    }

    private func runTranscript(_ run: CouncilRun) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CouncilSpacing.xl) {
                runHeader(run)

                ForEach(displayedStages(for: run), id: \.self) { stage in
                    stageSection(stage, run: run)
                }
            }
            .padding(CouncilSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func runHeader(_ run: CouncilRun) -> some View {
        VStack(alignment: .leading, spacing: CouncilSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: CouncilSpacing.xxs) {
                    Text(run.mode.title)
                        .font(CouncilTypography.emptyStateTitle)
                    Text(run.stage.title)
                        .font(CouncilTypography.detail)
                        .foregroundStyle(stageColor(run.stage))
                }

                Spacer()

                if coordinator.isRunning {
                    ProgressView()
                        .controlSize(.small)

                    Button(run.stopAfterCurrentStage ? "Continue Through Stages" : "Stop After This Stage") {
                        coordinator.toggleStopAfterCurrentStage()
                    }
                    .controlSize(.small)

                    Button("Stop Now", role: .destructive) {
                        coordinator.stopNow()
                    }
                    .controlSize(.small)
                }
            }

            Text(run.question)
                .font(CouncilTypography.body)
                .textSelection(.enabled)

            HStack(spacing: CouncilSpacing.md) {
                Label(
                    run.freshChatIsolation ? "Fresh-chat isolated" : "Existing conversations reused",
                    systemImage: run.freshChatIsolation ? "sparkles.rectangle.stack" : "bubble.left.and.bubble.right"
                )
                Text("Chairman: ChatGPT")
                Text("Saved locally")
            }
            .font(CouncilTypography.meta)
            .foregroundStyle(.secondary)
        }
        .padding(CouncilSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: CouncilMetrics.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func stageSection(_ stage: CouncilStage, run: CouncilRun) -> some View {
        let turns = run.turns.filter { $0.stage == stage }
        return VStack(alignment: .leading, spacing: CouncilSpacing.md) {
            Text(stage.title)
                .font(CouncilTypography.sectionTitle)

            if turns.isEmpty {
                Text(run.stage == stage ? "Preparing this stage…" : "Not reached.")
                    .font(CouncilTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(turns) { turn in
                    turnCard(turn, stage: stage)
                }
            }
        }
    }

    private func turnCard(_ turn: CouncilTurn, stage: CouncilStage) -> some View {
        let providerName = BuiltInProviders.byID[turn.providerID]?.displayName ?? turn.providerID.rawValue
        let isDissent = stage == .ratifyOrDissent
            && turn.responseText?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("DISSENT") == true

        return VStack(alignment: .leading, spacing: CouncilSpacing.md) {
            HStack {
                Text(stage == .chairmanSynthesis ? "ChatGPT Chairman" : providerName)
                    .font(CouncilTypography.detailStrong)

                statusBadge(turn.status)

                if isDissent {
                    Text("DISSENT")
                        .font(CouncilTypography.compactPill)
                        .foregroundStyle(.white)
                        .padding(.horizontal, CouncilSpacing.sm)
                        .padding(.vertical, CouncilSpacing.xxs)
                        .background(Capsule().fill(Color.red))
                }

                Spacer()

                if let response = turn.responseText, !response.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(response, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                if turn.status == .failed || turn.status == .timedOut || turn.status == .cancelled {
                    Button("Retry") {
                        onRetry(turn.id)
                    }
                    .controlSize(.small)
                    .disabled(coordinator.isRunning)
                }
            }

            if let response = turn.responseText, !response.isEmpty {
                Text(response)
                    .font(CouncilTypography.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = turn.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(CouncilTypography.detail)
                    .foregroundStyle(.red)
            } else {
                Text(statusDescription(turn.status))
                    .font(CouncilTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(CouncilSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: CouncilMetrics.cardCornerRadius, style: .continuous)
                .fill(isDissent ? Color.red.opacity(0.12) : Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CouncilMetrics.cardCornerRadius, style: .continuous)
                .stroke(isDissent ? Color.red.opacity(0.8) : Color(nsColor: .separatorColor), lineWidth: isDissent ? 2 : 1)
        )
    }

    private func statusBadge(_ status: CouncilTurnStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(CouncilTypography.compactPill)
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, CouncilSpacing.sm)
            .padding(.vertical, CouncilSpacing.xxs)
            .background(Capsule().fill(statusColor(status).opacity(0.12)))
    }

    private func displayedStages(for run: CouncilRun) -> [CouncilStage] {
        var stages: [CouncilStage] = [.preparing]
        stages.append(contentsOf: CouncilRunStateMachine.stages(for: run.mode))
        return stages
    }

    private func statusDescription(_ status: CouncilTurnStatus) -> String {
        switch status {
        case .queued: "Queued"
        case .submitting: "Submitting prompt…"
        case .waiting: "Waiting for the provider to finish streaming…"
        case .succeeded: "Completed"
        case .failed: "Failed"
        case .timedOut: "Timed out"
        case .cancelled: "Cancelled"
        }
    }

    private func statusColor(_ status: CouncilTurnStatus) -> Color {
        switch status {
        case .queued: .secondary
        case .submitting, .waiting: .orange
        case .succeeded: .green
        case .failed, .timedOut, .cancelled: .red
        }
    }

    private func stageColor(_ stage: CouncilStage) -> Color {
        switch stage {
        case .completed: .green
        case .failed: .red
        case .stopped: .orange
        default: .secondary
        }
    }
}
