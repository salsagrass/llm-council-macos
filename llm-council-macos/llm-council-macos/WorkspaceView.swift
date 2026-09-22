//
//  WorkspaceView.swift
//  LLM Council
//
//

import AppKit
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    let adapters: [ProviderID: any ProviderAutomationAdapter]
    @ObservedObject var chrome: WorkspaceChromeState
    var composerFocusRequestToken: Int = 0

    @StateObject private var webViewHub = WebViewHub()
    @StateObject private var captureContext = CouncilCaptureContext()
    @StateObject private var councilCoordinator = CouncilCoordinator()
    @State private var splitLayoutResetKey = 0
    @State private var paneWindowStart = 0
    @State private var pendingDispatchTask: Task<Void, Never>?
    @State private var pendingCouncilStartTask: Task<Void, Never>?
    @State private var composerFocused = false
    @State private var councilProviderIDs: Set<ProviderID> = [.chatGPT, .claude, .gemini]
    @State private var freshChatIsolation = true
    @State private var councilStartError: String?

    private let maxComparePanes = 3
    private let composerDockMinHeight: CGFloat = 132

    private var visibleProviders: [ProviderDefinition] {
        store.orderedVisibleProviders
    }

    private var displayedProviders: [ProviderDefinition] {
        if let focusedID = store.focusedProviderID,
           store.state(for: focusedID).isVisible,
           let focused = store.definition(for: focusedID)
        {
            return [focused]
        }
        let total = visibleProviders.count
        guard total > maxComparePanes else {
            return visibleProviders
        }
        let start = min(max(0, paneWindowStart), max(0, total - maxComparePanes))
        let end = min(total, start + maxComparePanes)
        return Array(visibleProviders[start ..< end])
    }

    private var displayedProviderIDs: Set<ProviderID> {
        Set(displayedProviders.map(\.id))
    }

    var body: some View {
        workspaceRoot
    }

    private var workspaceRoot: some View {
        configuredWorkspaceSurface
            .onReceive(NotificationCenter.default.publisher(for: .councilSendPrompt)) { _ in
                performPrimaryAction()
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilNewChatAll)) { _ in
                startNewChats()
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilToggleFocusMode)) { _ in
                store.toggleFocusMode()
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilRestoreSession)) { note in
                restoreSessionInMountedPanes(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilEqualizePanes)) { _ in
                resetSplitLayout()
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilPageVisibleProvidersPrevious)) { _ in
                pagePanes(by: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilPageVisibleProvidersNext)) { _ in
                pagePanes(by: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilCaptureWorkspaceScreenshot)) { _ in
                exportWorkspaceScreenshot()
            }
            .onChange(of: visibleProviders.map(\.id)) {
                normalizePaneWindow()
                resetSplitLayout()
            }
            .onChange(of: store.focusedProviderID) {
                resetSplitLayout()
            }
            .onChange(of: store.pageZoom) { _, newValue in
                webViewHub.setGlobalZoom(newValue)
            }
            .onChange(of: composerFocusRequestToken) {
                composerFocused = true
            }
            .onAppear {
                normalizePaneWindow()
                webViewHub.configure(adapters: adapters)
                webViewHub.setGlobalZoom(store.pageZoom)
            }
            .onDisappear {
                pendingDispatchTask?.cancel()
                pendingCouncilStartTask?.cancel()
            }
    }

    private var configuredWorkspaceSurface: AnyView {
        AnyView(
            VStack(spacing: 0) {
                workspaceModeBar

                workspaceBackground
                    .overlay {
                        captureAnchor
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                composerDock
                    .frame(minHeight: composerDockMinHeight, maxHeight: composerDockMinHeight)
            }
            .frame(minWidth: 860, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
            .tint(.accentColor)
        )
    }

    private var workspaceBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            workspaceCanvas
                .opacity(chrome.councilMode == .compare ? 1 : 0.001)
                .allowsHitTesting(chrome.councilMode == .compare)

            if chrome.councilMode.isCouncil {
                CouncilRunView(
                    coordinator: councilCoordinator,
                    mode: chrome.councilMode,
                    selectedProviderIDs: $councilProviderIDs,
                    freshChatIsolation: $freshChatIsolation,
                    startErrorMessage: councilStartError,
                    onRetry: { turnID in
                        councilCoordinator.retry(turnID: turnID, client: webViewHub)
                    }
                )
            }
        }
    }

    private var workspaceModeBar: some View {
        HStack(spacing: CouncilSpacing.md) {
            Text("Mode")
                .font(CouncilTypography.detailStrong)

            Picker(
                "Mode",
                selection: Binding(
                    get: { chrome.councilMode },
                    set: { newMode in
                        guard !councilCoordinator.isRunning else { return }
                        chrome.councilMode = newMode
                        councilStartError = nil
                    }
                )
            ) {
                ForEach(CouncilMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(councilCoordinator.isRunning)
            .frame(maxWidth: 560)

            Spacer()

            if chrome.councilMode.isCouncil {
                Text(councilCoordinator.activeRun?.stage.title ?? "Ready for a new council run")
                    .font(CouncilTypography.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, CouncilSpacing.xl)
        .padding(.vertical, CouncilSpacing.sm)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var captureAnchor: some View {
        CouncilCaptureAnchor(context: captureContext)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    private var workspaceCanvas: some View {
        VStack(spacing: 0) {
            if displayedProviders.isEmpty {
                emptyCanvasState
            } else {
                if !store.focusModeEnabled && visibleProviders.count > maxComparePanes {
                    panePagingBar
                }

                HSplitView {
                    ForEach(displayedProviders) { provider in
                        ProviderPaneView(
                            provider: provider,
                            paneState: Binding(
                                get: { store.state(for: provider.id) },
                                set: { store.replacePaneState($0) }
                            ),
                            isFocused: store.focusedProviderID == provider.id,
                            isSelected: chrome.selectedProviderID == provider.id,
                            isActivated: chrome.isProviderActivated(provider.id),
                            adapter: adapters[provider.id],
                            webViewHub: webViewHub,
                            onSelect: {
                                chrome.selectProvider(provider.id)
                            },
                            onActivate: {
                                activateProvider(provider.id)
                            },
                            onFocusToggle: {
                                if store.focusedProviderID == provider.id {
                                    store.setFocusedProvider(nil)
                                } else {
                                    store.setFocusedProvider(provider.id)
                                }
                                chrome.selectProvider(provider.id)
                            },
                            onHide: {
                                store.setPaneVisibility(provider.id, isVisible: false)
                                if chrome.selectedProviderID == provider.id {
                                    chrome.selectWorkspace()
                                }
                            },
                            onIncludeToggle: {
                                store.setIncludedInSend(provider.id, isIncluded: !store.state(for: provider.id).isIncludedInSend)
                            },
                            onOpenHome: {
                                activateProvider(provider.id)
                                DispatchQueue.main.async {
                                    webViewHub.openHome(providerID: provider.id)
                                }
                            }
                        )
                        .frame(minWidth: 320, minHeight: 280)
                    }
                }
                .id(splitLayoutResetKey)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var emptyCanvasState: some View {
        VStack(spacing: CouncilSpacing.lg) {
            Image(systemName: "rectangle.split.3x1")
                .font(CouncilTypography.largeIcon)
                .foregroundStyle(.secondary)
            Text("No providers are visible")
                .font(CouncilTypography.emptyStateTitle)
            Text("Reveal providers from the sidebar to start comparing responses.")
                .font(CouncilTypography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panePagingBar: some View {
        HStack(spacing: CouncilSpacing.md) {
            Button {
                pagePanes(by: -1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .font(CouncilTypography.detail)
            .controlSize(CouncilControls.compact)
            .disabled(!canPageBackward)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CouncilSpacing.sm) {
                    ForEach(visibleProviders) { provider in
                        Button {
                            showProvider(provider.id)
                            chrome.selectProvider(provider.id)
                        } label: {
                            Text(provider.displayName)
                                .font(CouncilTypography.compactPill)
                                .padding(.horizontal, CouncilSpacing.lg)
                                .padding(.vertical, CouncilSpacing.xs)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(displayedProviderIDs.contains(provider.id) ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pane-chip-\(provider.id.rawValue)")
                    }
                }
                .padding(.vertical, CouncilSpacing.xs)
            }

            Button {
                pagePanes(by: 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .font(CouncilTypography.detail)
            .controlSize(CouncilControls.compact)
            .disabled(!canPageForward)
        }
        .padding(.horizontal, CouncilSpacing.xl)
        .padding(.vertical, CouncilSpacing.xxs)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var composerDock: some View {
        VStack(alignment: .leading, spacing: CouncilSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: CouncilSpacing.md) {
                Text(chrome.councilMode == .compare ? "Prompt" : "Council Question")
                    .font(CouncilTypography.promptLabel)
                    .foregroundStyle(.secondary)

                compactTargetChipRow

                Spacer()

                Text(composerStatusMessage)
                    .font(CouncilTypography.promptStatus)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("Cmd+Return")
                    .font(CouncilTypography.promptStatus)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: CouncilSpacing.md) {
                ZStack(alignment: .topLeading) {
                    CouncilComposerTextView(text: $store.composerText, isFocused: $composerFocused) {
                        performPrimaryAction()
                    }
                    .font(CouncilTypography.promptInput)
                    .frame(maxWidth: .infinity, minHeight: CouncilMetrics.textFieldMinHeight)

                    if store.composerText.isEmpty {
                        Text(chrome.councilMode == .compare ? "Write once, compare across providers" : "Ask the council one question")
                            .font(CouncilTypography.promptInput)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .padding(.leading, 8)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, CouncilSpacing.lg)
                .padding(.vertical, CouncilSpacing.md)
                .frame(maxWidth: .infinity, minHeight: CouncilMetrics.textFieldMinHeight)
                .background(
                    RoundedRectangle(cornerRadius: CouncilMetrics.fieldCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CouncilMetrics.fieldCornerRadius, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

                if chrome.councilMode.isCouncil, councilCoordinator.isRunning {
                    Button("Stop") {
                        councilCoordinator.stopNow()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(CouncilControls.standard)
                    .accessibilityIdentifier("council-stop-button")
                } else if store.dispatchState.isActive {
                    Button("Cancel") {
                        cancelCurrentDispatch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(CouncilControls.standard)
                    .accessibilityIdentifier("composer-cancel-button")
                } else if chrome.councilMode == .compare,
                          let lastPrompt = store.dispatchState.lastPrompt,
                          !lastPrompt.isEmpty
                {
                    Button("Resend") {
                        store.updateComposer(with: lastPrompt)
                        sendToActiveProviders()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(CouncilControls.standard)
                    .accessibilityIdentifier("composer-resend-button")
                }

                Button {
                    performPrimaryAction()
                } label: {
                    Label(primaryButtonTitle, systemImage: chrome.councilMode == .compare ? "paperplane.fill" : "person.3.sequence.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(CouncilControls.standard)
                .disabled(primaryActionDisabled)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityIdentifier("send-all-button")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, CouncilSpacing.md)
        .padding(.bottom, CouncilSpacing.md)
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var composerTargetLine: String {
        if currentTargetProviderIDs.isEmpty {
            return "No provider targets selected"
        }
        return "Send to \(currentTargetProviderIDs.count) provider\(currentTargetProviderIDs.count == 1 ? "" : "s")"
    }

    private var currentTargetProviderIDs: [ProviderID] {
        if chrome.councilMode.isCouncil {
            return [ProviderID.chatGPT, .claude, .gemini].filter { councilProviderIDs.contains($0) }
        }
        return store.dispatchProviderIDs
    }

    private var composerStatusMessage: String {
        if chrome.councilMode.isCouncil {
            if let error = councilStartError { return error }
            return councilCoordinator.activeRun?.stage.title ?? "Ready"
        }
        return store.dispatchState.message
    }

    private var primaryButtonTitle: String {
        if chrome.councilMode.isCouncil {
            return councilCoordinator.isRunning ? "Running" : "Start Council"
        }
        return store.dispatchState.isActive ? "Sending" : "Send"
    }

    private var primaryActionDisabled: Bool {
        let questionIsEmpty = WorkspaceStore.normalizedPrompt(store.composerText).isEmpty
        if chrome.councilMode.isCouncil {
            return questionIsEmpty
                || councilCoordinator.isRunning
                || currentTargetProviderIDs.count < 2
                || !currentTargetProviderIDs.contains(.chatGPT)
        }
        return questionIsEmpty || store.dispatchState.isActive
    }

    private var compactTargetChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CouncilSpacing.xs) {
                ForEach(currentTargetProviderIDs.prefix(3), id: \.self) { providerID in
                    if let provider = store.definition(for: providerID) {
                        Text(provider.displayName)
                            .font(CouncilTypography.compactPill)
                            .padding(.horizontal, CouncilSpacing.sm)
                            .padding(.vertical, CouncilSpacing.xxs)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }

                if currentTargetProviderIDs.count > 3 {
                    Text("+\(currentTargetProviderIDs.count - 3)")
                        .font(CouncilTypography.compactPill)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func activateProvider(_ providerID: ProviderID) {
        chrome.activateProvider(providerID)
        chrome.selectProvider(providerID)
        resetSplitLayout()
    }

    private func performPrimaryAction() {
        if chrome.councilMode.isCouncil {
            startCouncilRun()
        } else {
            sendToActiveProviders()
        }
    }

    private func startCouncilRun() {
        guard !councilCoordinator.isRunning else { return }
        pendingCouncilStartTask?.cancel()
        let question = WorkspaceStore.normalizedPrompt(store.composerText)
        let participants = currentTargetProviderIDs
        guard !question.isEmpty else {
            councilStartError = CouncilRunValidationError.emptyQuestion.localizedDescription
            return
        }
        guard participants.count >= 2, participants.contains(.chatGPT) else {
            councilStartError = CouncilRunValidationError.atLeastTwoProvidersRequired.localizedDescription
            return
        }

        councilStartError = nil
        webViewHub.configure(adapters: adapters)
        for providerID in participants {
            if !store.state(for: providerID).isVisible {
                store.setPaneVisibility(providerID, isVisible: true)
            }
        }
        chrome.activateProviders(participants)
        normalizePaneWindow()
        resetSplitLayout()

        pendingCouncilStartTask = Task { @MainActor in
            let mounted = await webViewHub.waitForMountedProviders(participants, timeout: 5)
            guard !Task.isCancelled else { return }
            guard mounted else {
                councilStartError = "Unable to mount every selected provider WebView. Switch to Compare and open each provider once."
                return
            }

            do {
                try councilCoordinator.start(
                    question: question,
                    mode: chrome.councilMode,
                    participantProviderIDs: participants,
                    freshChatIsolation: freshChatIsolation,
                    client: webViewHub
                )
                _ = store.registerPromptSend()
            } catch {
                councilStartError = error.localizedDescription
            }
        }
    }

    private func sendToActiveProviders() {
        pendingDispatchTask?.cancel()

        let prompt = WorkspaceStore.normalizedPrompt(store.composerText)
        guard !prompt.isEmpty else {
            store.markPromptDispatchBootstrapFailed(prompt: prompt, targets: [], message: "Enter a prompt first.")
            return
        }

        let targets = store.dispatchProviderIDs
        guard !targets.isEmpty else {
            store.markPromptDispatchBootstrapFailed(prompt: prompt, targets: [], message: "No active providers selected.")
            return
        }

        _ = store.registerPromptSend()

        let idleTargets = targets.filter { !chrome.isProviderActivated($0) }
        if idleTargets.isEmpty {
            performDispatch(prompt: prompt, targets: targets)
            return
        }

        for providerID in targets {
            store.setAutomationState(providerID, level: .running, message: idleTargets.contains(providerID) ? "Opening chat" : "Sending")
        }

        store.beginPromptBootstrap(prompt: prompt, targets: targets)
        chrome.activateProviders(idleTargets)
        resetSplitLayout()

        pendingDispatchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else {
                return
            }

            var openedCount = 0
            for providerID in idleTargets {
                if webViewHub.openNewChat(providerID: providerID) || webViewHub.openHome(providerID: providerID) {
                    openedCount += 1
                }
            }

            if openedCount == 0 {
                store.markPromptDispatchBootstrapFailed(
                    prompt: prompt,
                    targets: targets,
                    message: "Unable to prepare provider sessions. Open a provider pane first."
                )
                return
            }

            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled else {
                return
            }

            performDispatch(prompt: prompt, targets: targets)
        }
    }

    private func performDispatch(prompt: String, targets: [ProviderID]) {
        store.beginPromptDispatch(prompt: prompt, targets: targets)
        for providerID in targets {
            store.setAutomationState(providerID, level: .running, message: "Sending")
        }

        webViewHub.sendPrompt(prompt, to: targets, using: adapters) { results in
            let currentPhase = store.dispatchState.phase
            for result in results {
                store.setAutomationState(
                    result.providerID,
                    level: result.success ? .ready : .failed,
                    message: result.message
                )
            }

            if currentPhase != .cancelled {
                store.completePromptDispatch(results: results, prompt: prompt)
            }
        }
    }

    private func cancelCurrentDispatch() {
        pendingDispatchTask?.cancel()
        pendingDispatchTask = nil
        store.cancelPromptDispatchTracking()
    }

    private func startNewChats() {
        let targets = store.orderedVisibleProviders.map(\.id)
        chrome.activateProviders(targets)
        resetSplitLayout()

        DispatchQueue.main.async {
            for providerID in targets {
                _ = webViewHub.openNewChat(providerID: providerID)
                store.setAutomationState(providerID, level: .running, message: "Starting new chat")
            }
            store.resetPromptDispatchState()
        }
    }

    private var canPageBackward: Bool {
        paneWindowStart > 0
    }

    private var canPageForward: Bool {
        paneWindowStart + maxComparePanes < visibleProviders.count
    }

    private func pagePanes(by delta: Int) {
        paneWindowStart = min(
            max(0, paneWindowStart + delta),
            max(0, visibleProviders.count - maxComparePanes)
        )
        resetSplitLayout()
    }

    private func showProvider(_ providerID: ProviderID) {
        guard let index = visibleProviders.firstIndex(where: { $0.id == providerID }) else {
            return
        }
        if index < paneWindowStart {
            paneWindowStart = index
        } else if index >= paneWindowStart + maxComparePanes {
            paneWindowStart = index - (maxComparePanes - 1)
        }
        resetSplitLayout()
    }

    private func normalizePaneWindow() {
        let maxStart = max(0, visibleProviders.count - maxComparePanes)
        if paneWindowStart > maxStart {
            paneWindowStart = maxStart
        }
        if paneWindowStart < 0 {
            paneWindowStart = 0
        }
    }

    private func resetSplitLayout() {
        splitLayoutResetKey += 1
    }

    private func restoreSessionInMountedPanes(_ note: Notification) {
        guard let session = note.object as? SavedWorkspaceSession else {
            return
        }
        let visibleSet = Set(session.visibleProviderIDs)
        for provider in store.orderedProviders where visibleSet.contains(provider.id) {
            chrome.activateProvider(provider.id)
            if let restoredURL = session.providerChatURLs[provider.id] {
                _ = webViewHub.openRestoredChat(providerID: provider.id, restoredURLString: restoredURL)
            } else {
                _ = webViewHub.openHome(providerID: provider.id)
            }
        }
        normalizePaneWindow()
        resetSplitLayout()
    }

    private func exportWorkspaceScreenshot() {
        CouncilScreenshotExporter.exportCurrentWorkspace(
            from: captureContext,
            visibleProviderNames: displayedProviders.map(\.displayName),
            includedProviderCount: store.dispatchProviderIDs.count
        )
    }
}

struct CouncilComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.setAccessibilityIdentifier("composer-text-editor")

        guard let textView = scrollView.documentView as? NSTextView else {
            assertionFailure("NSTextView.scrollableTextView() did not provide an NSTextView")
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont(name: "Avenir Next", size: 14) ?? NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        Self.applyFocusRequest(isFocused, to: textView)
    }

    static func applyFocusRequest(_ isFocused: Bool, to textView: NSTextView) {
        guard isFocused,
              let window = textView.window,
              window.firstResponder !== textView
        else {
            return
        }
        window.makeFirstResponder(textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CouncilComposerTextView

        init(parent: CouncilComposerTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            guard modifiers.contains(.command),
                  !modifiers.contains(.shift),
                  !modifiers.contains(.option),
                  !modifiers.contains(.control)
            else {
                return false
            }

            DispatchQueue.main.async {
                self.parent.onSubmit()
            }
            return true
        }
    }
}

private struct ProviderPaneView: View {
    let provider: ProviderDefinition
    @Binding var paneState: ProviderPaneState
    let isFocused: Bool
    let isSelected: Bool
    let isActivated: Bool
    let adapter: (any ProviderAutomationAdapter)?
    let webViewHub: WebViewHub
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onFocusToggle: () -> Void
    let onHide: () -> Void
    let onIncludeToggle: () -> Void
    let onOpenHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                if !isActivated {
                    idleState
                } else if let adapter {
                    WebViewPane(provider: provider, adapter: adapter, paneState: $paneState, hub: webViewHub)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("webview-pane-\(provider.id.rawValue)")
                } else {
                    unsupportedState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(backgroundFill)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var header: some View {
        HStack(spacing: CouncilSpacing.md) {
            Menu {
                Button(paneState.isIncludedInSend ? "Remove from Send" : "Include in Send") {
                    onIncludeToggle()
                }

                Button(isFocused ? "Exit Focus" : "Focus Provider") {
                    onFocusToggle()
                }

                Divider()

                Button("Open Home") {
                    onOpenHome()
                }

                Button("New Chat") {
                    onActivate()
                    DispatchQueue.main.async {
                        _ = webViewHub.openNewChat(providerID: provider.id)
                    }
                }

                Divider()

                Button("Hide Pane") {
                    onHide()
                }
            } label: {
                HStack(spacing: CouncilSpacing.sm) {
                    Text(provider.displayName)
                        .font(isSelected ? CouncilTypography.detailStrong : CouncilTypography.detail)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    statusDot

                    Image(systemName: "chevron.down")
                        .font(CouncilTypography.microIcon)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .help("Provider actions and compare options")

            Spacer(minLength: CouncilSpacing.xs)

            if isActivated {
                headerIconButton(systemName: "arrow.clockwise", helpText: "Reload provider") {
                    webViewHub.reload(providerID: provider.id)
                }
            } else {
                headerIconButton(systemName: "sparkles", helpText: "Start provider chat") {
                    onActivate()
                    DispatchQueue.main.async {
                        _ = webViewHub.openNewChat(providerID: provider.id)
                    }
                }
            }
        }
        .padding(.horizontal, CouncilSpacing.md)
        .padding(.vertical, CouncilSpacing.xxs)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(providerAccent.opacity(isSelected ? 0.9 : 0.45))
                .frame(height: 2)
        }
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    private var providerGlyph: some View {
        Text(String(provider.displayName.prefix(1)))
            .font(CouncilTypography.captionStrong)
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(width: CouncilMetrics.paneGlyphSize, height: CouncilMetrics.paneGlyphSize)
            .background(
                Circle()
                    .fill(isSelected ? providerAccent : providerAccent.opacity(0.24))
            )
    }

    private var statusDot: some View {
        Circle()
            .fill(statusTint)
            .frame(width: CouncilMetrics.statusDotSize, height: CouncilMetrics.statusDotSize)
            .help(paneState.automationState.message)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.08)
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    private var statusTint: Color {
        switch paneState.automationState.level {
        case .idle:
            return .secondary.opacity(0.65)
        case .ready:
            return .green
        case .running:
            return .orange
        case .failed:
            return .red
        }
    }

    private var providerAccent: Color {
        switch provider.id {
        case .chatGPT:
            return Color(red: 0.13, green: 0.51, blue: 0.95)
        case .claude:
            return Color(red: 0.86, green: 0.56, blue: 0.32)
        case .gemini:
            return Color(red: 0.37, green: 0.52, blue: 0.98)
        case .grok:
            return Color(red: 0.58, green: 0.58, blue: 0.62)
        case .perplexity:
            return Color(red: 0.4, green: 0.58, blue: 0.89)
        case .deepSeek:
            return Color(red: 0.45, green: 0.58, blue: 0.72)
        }
    }

    private var headerBackground: some View {
        Rectangle()
            .fill(isSelected ? providerAccent.opacity(0.12) : providerAccent.opacity(0.05))
            .background(Color(nsColor: .controlBackgroundColor))
    }

    private func headerIconButton(systemName: String, helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(CouncilTypography.compactIcon)
                .frame(width: CouncilMetrics.iconButtonSize, height: CouncilMetrics.iconButtonSize)
        }
        .buttonStyle(.borderless)
        .help(helpText)
    }

    private var idleState: some View {
        VStack(spacing: CouncilSpacing.lg) {
            providerGlyph
                .frame(width: 56, height: 56)

            VStack(spacing: CouncilSpacing.xxs) {
                Text(provider.displayName)
                    .font(CouncilTypography.emptyStateTitle)
                Text("Open the provider or start a chat here. The shared composer remains available below.")
                    .font(CouncilTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: CouncilSpacing.md) {
                Button {
                    onActivate()
                    DispatchQueue.main.async {
                        _ = webViewHub.openNewChat(providerID: provider.id)
                    }
                } label: {
                    Label("Start Chat", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(CouncilControls.standard)

                Button {
                    onOpenHome()
                } label: {
                    Label("Open Provider", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(CouncilControls.standard)
            }
        }
        .padding(CouncilSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: CouncilSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(CouncilTypography.mediumIcon)
                .foregroundStyle(.orange)
            Text("Missing adapter for \(provider.displayName)")
                .font(CouncilTypography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let councilSendPrompt = Notification.Name("LLMCouncil.sendPrompt")
    static let councilNewChatAll = Notification.Name("LLMCouncil.newChatAll")
    static let councilToggleFocusMode = Notification.Name("LLMCouncil.toggleFocusMode")
    static let councilRestoreSession = Notification.Name("LLMCouncil.restoreSession")
    static let councilEqualizePanes = Notification.Name("LLMCouncil.equalizePanes")
    static let councilPageVisibleProvidersPrevious = Notification.Name("LLMCouncil.pageVisibleProvidersPrevious")
    static let councilPageVisibleProvidersNext = Notification.Name("LLMCouncil.pageVisibleProvidersNext")
    static let councilShowShortcutLegend = Notification.Name("LLMCouncil.showShortcutLegend")
    static let councilToggleInspector = Notification.Name("LLMCouncil.toggleInspector")
    static let councilCaptureWorkspaceScreenshot = Notification.Name("LLMCouncil.captureWorkspaceScreenshot")
}
