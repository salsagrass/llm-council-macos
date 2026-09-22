//
//  ContentView.swift
//  LLM Council
//
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var store: WorkspaceStore
    let adapters: [ProviderID: any ProviderAutomationAdapter]

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("council.theme.selection") private var selectedThemeRawValue = CouncilTheme.Selection.system.persistedValue
    @State private var isShortcutLegendVisible = false
    @State private var composerFocusRequestToken = 0
    @StateObject private var chrome = WorkspaceChromeState()

    private var selectedTheme: CouncilTheme.Selection {
        CouncilTheme.Selection(persistedValue: selectedThemeRawValue)
    }

    private var toolbarStatus: String {
        if store.dispatchState.isActive || store.dispatchState.phase == .failed || store.dispatchState.phase == .succeeded {
            return store.dispatchState.message
        }
        if let focusedID = store.focusedProviderID,
           let focusedProvider = store.definition(for: focusedID)
        {
            return "Focus on \(focusedProvider.displayName)"
        }
        return "\(store.dispatchProviderIDs.count) included"
    }

    var body: some View {
        ZStack(alignment: .center) {
            NavigationSplitView {
                CouncilSidebarView(
                    chrome: chrome,
                    activeProviderCount: store.orderedVisibleProviders.count,
                    totalProviderCount: store.orderedProviders.count,
                    providers: store.orderedProviders,
                    paneStates: store.paneStates,
                    historyEntries: store.promptHistory,
                    promptPresets: store.promptPresets,
                    savedSessions: store.savedSessions,
                    onSelectWorkspace: {
                        chrome.selectWorkspace()
                    },
                    onSelectProvider: { providerID in
                        revealAndSelectProvider(providerID)
                    },
                    onSetProviderVisible: { providerID, isVisible in
                        store.setPaneVisibility(providerID, isVisible: isVisible)
                        if isVisible {
                            chrome.selectProvider(providerID)
                        } else if chrome.selectedProviderID == providerID {
                            chrome.selectWorkspace()
                        }
                    },
                    onToggleProviderInclude: { providerID in
                        store.setIncludedInSend(providerID, isIncluded: !store.state(for: providerID).isIncludedInSend)
                    },
                    onApplyHistory: { entry in
                        applyPromptFromSidebar(entry.text)
                    },
                    onDeleteHistoryEntry: { entry in
                        store.deleteHistoryEntry(entry.id)
                    },
                    onClearHistory: {
                        store.clearHistory()
                    },
                    onApplyPreset: { preset in
                        store.applyPreset(preset.id)
                        requestComposerFocus()
                    },
                    onRestoreSession: { session in
                        restoreSession(session)
                    }
                )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
            } detail: {
                WorkspaceView(
                    store: store,
                    adapters: adapters,
                    chrome: chrome,
                    composerFocusRequestToken: composerFocusRequestToken
                )
                .inspector(isPresented: $chrome.inspectorPresented) {
                    WorkspaceInspectorView(
                        store: store,
                        chrome: chrome
                    )
                }
                .inspectorColumnWidth(min: 260, ideal: 320, max: 380)
            }
            .navigationSplitViewStyle(.balanced)
            .preferredColorScheme(selectedTheme.colorSchemeOverride)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        toggleFocusMode()
                    } label: {
                        Label(store.focusModeEnabled ? "Compare" : "Focus", systemImage: store.focusModeEnabled ? "square.split.2x1" : "scope")
                    }
                    .help(store.focusModeEnabled ? "Exit focus mode and compare visible providers." : "Focus the selected provider.")
                    .accessibilityIdentifier("toolbar-focus-toggle")
                    .controlSize(CouncilControls.compact)

                    Button {
                        chrome.inspectorPresented.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .help("Show or hide the workspace inspector.")
                    .accessibilityIdentifier("toolbar-inspector-toggle")
                    .controlSize(CouncilControls.compact)

                    Button {
                        NotificationCenter.default.post(name: .councilCaptureWorkspaceScreenshot, object: nil)
                    } label: {
                        Label("Screenshot", systemImage: "camera")
                    }
                    .help("Export a shareable screenshot of the current workspace.")
                    .accessibilityIdentifier("toolbar-screenshot-button")
                    .controlSize(CouncilControls.compact)

                    Button {
                        store.requestSendCurrentPrompt()
                    } label: {
                        Label(
                            chrome.councilMode.isCouncil ? "Start Council" : "Send",
                            systemImage: chrome.councilMode.isCouncil ? "person.3.sequence.fill" : "paperplane.fill"
                        )
                    }
                    .disabled(WorkspaceStore.normalizedPrompt(store.composerText).isEmpty)
                    .help(chrome.councilMode.isCouncil ? "Start the selected council protocol." : "Send the current prompt to the included providers.")
                    .accessibilityIdentifier("toolbar-send-button")
                    .controlSize(CouncilControls.compact)

                    Text(toolbarStatus)
                        .font(CouncilTypography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("toolbar-compact-stat")

                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open LLM Council settings.")
                    .accessibilityIdentifier("toolbar-settings-link")
                }
            }
            .onAppear {
                chrome.syncActivatedProviders(from: store.paneStates)
                if let focusedID = store.focusedProviderID {
                    chrome.selectProvider(focusedID)
                } else {
                    chrome.selectWorkspace()
                }
            }
            .onReceive(store.$paneStates) { paneStates in
                chrome.syncActivatedProviders(from: paneStates)
            }
            .onReceive(store.$focusedProviderID) { focusedProviderID in
                guard let focusedProviderID else {
                    return
                }
                chrome.selectProvider(focusedProviderID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilToggleInspector)) { _ in
                chrome.inspectorPresented.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .councilShowShortcutLegend)) { _ in
                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                    isShortcutLegendVisible.toggle()
                }
            }

            if isShortcutLegendVisible {
                Color.black.opacity(0.32)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            isShortcutLegendVisible = false
                        }
                    }
            }

            if isShortcutLegendVisible {
                shortcutLegendOverlay
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .animation(.spring(response: 0.24, dampingFraction: 0.85), value: isShortcutLegendVisible)
            }
        }
    }

    private var activeThemePalette: CouncilTheme.Palette {
        selectedTheme.palette(for: colorScheme)
    }

    private var shortcutLegendOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: CouncilSpacing.xxs) {
                    Text("Keyboard Shortcuts")
                        .font(CouncilTypography.overlayTitle)
                        .foregroundStyle(activeThemePalette.primaryText)
                    Text("Quick reference for keyboard-driven workflows")
                        .font(CouncilTypography.detail)
                        .foregroundStyle(activeThemePalette.secondaryText)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                        isShortcutLegendVisible = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(CouncilTypography.overlayDismiss)
                        .foregroundStyle(activeThemePalette.sectionIcon)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, CouncilSpacing.xxl)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(CouncilShortcutGuide.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(CouncilTypography.sectionTitle)
                                .foregroundStyle(activeThemePalette.sectionIcon)
                                .padding(.horizontal, CouncilSpacing.xxl)

                            VStack(spacing: 10) {
                                ForEach(section.shortcuts) { shortcut in
                                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(shortcut.action)
                                                .font(CouncilTypography.detailStrong)
                                                .foregroundStyle(activeThemePalette.primaryText)
                                            Text(shortcut.description)
                                                .font(CouncilTypography.meta)
                                                .foregroundStyle(activeThemePalette.secondaryText)
                                                .lineLimit(2)
                                                .truncationMode(.tail)
                                        }

                                        Spacer(minLength: 12)

                                        HStack(spacing: 5) {
                                            ForEach(shortcut.keyCombination, id: \.self) { key in
                                                Text(key)
                                                    .font(CouncilTypography.keycap)
                                                    .padding(.vertical, 5)
                                                    .padding(.horizontal, 8)
                                                    .background(activeThemePalette.cardFill)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .stroke(activeThemePalette.cardBorder, lineWidth: 1)
                                                    )
                                                    .foregroundStyle(activeThemePalette.primaryText)
                                            }
                                        }
                                        .accessibilityIdentifier("shortcut-keys-\(shortcut.id)")
                                    }
                                }
                            }
                            .padding(.horizontal, CouncilSpacing.xxl)
                            .padding(.bottom, 10)
                        }
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 18)
            }

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                    isShortcutLegendVisible = false
                }
            } label: {
                Text("Close")
                    .font(CouncilTypography.detailStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 160)
                    .padding(.vertical, 9)
                    .background(activeThemePalette.sectionIcon.opacity(0.9))
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: 600)
        .background(
            RoundedRectangle(cornerRadius: CouncilMetrics.heroCardCornerRadius, style: .continuous)
                .fill(activeThemePalette.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CouncilMetrics.heroCardCornerRadius, style: .continuous)
                        .stroke(activeThemePalette.cardBorder, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 30)
    }

    private func applyPromptFromSidebar(_ prompt: String) {
        chrome.revealSection(.history)
        store.updateComposer(with: prompt)
        requestComposerFocus()
    }

    private func requestComposerFocus() {
        composerFocusRequestToken += 1
    }

    private func revealAndSelectProvider(_ providerID: ProviderID) {
        if !store.state(for: providerID).isVisible {
            store.setPaneVisibility(providerID, isVisible: true)
        }
        chrome.selectProvider(providerID)
    }

    private func restoreSession(_ session: SavedWorkspaceSession) {
        guard store.applySavedSession(session.id) else {
            return
        }
        NotificationCenter.default.post(name: .councilRestoreSession, object: session)
        chrome.syncActivatedProviders(from: store.paneStates)
        if let focusedProviderID = store.focusedProviderID {
            chrome.selectProvider(focusedProviderID)
        } else {
            chrome.selectWorkspace()
        }
        requestComposerFocus()
    }

    private func toggleFocusMode() {
        if store.focusModeEnabled {
            store.setFocusedProvider(nil)
        } else if let selectedProviderID = chrome.selectedProviderID {
            store.setFocusedProvider(selectedProviderID)
        } else {
            store.toggleFocusMode()
        }
    }
}

private struct WorkspaceInspectorView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var chrome: WorkspaceChromeState

    @State private var sessionName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                workspaceSection
                layoutSection
                selectedProviderSection
                sessionsSection
                preferencesSection
            }
            .padding(16)
        }
        .background(.bar)
    }

    private var workspaceSection: some View {
        inspectorSection("Workspace") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(store.orderedVisibleProviders.count) visible • \(store.dispatchProviderIDs.count) included")
                    .font(CouncilTypography.caption)
                    .foregroundStyle(.secondary)

                Picker("Send Scope", selection: Binding(
                    get: { store.sendScope },
                    set: {
                        store.sendScope = $0
                        store.persist()
                    }
                )) {
                    Text("All Visible").tag(ComposerSendScope.allVisible)
                    Text("Included").tag(ComposerSendScope.includedOnly)
                }
                .pickerStyle(.segmented)

                Toggle("Clear composer after send", isOn: Binding(
                    get: { store.clearComposerAfterSend },
                    set: {
                        store.clearComposerAfterSend = $0
                        store.persist()
                    }
                ))
            }
        }
    }

    private var layoutSection: some View {
        inspectorSection("Layout & Commands") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Layout Preset", selection: Binding(
                    get: { selectedLayoutPresetID },
                    set: {
                        guard let newValue = $0 else {
                            return
                        }
                        store.applyLayoutPreset(newValue)
                    }
                )) {
                    ForEach(store.layoutPresets) { preset in
                        Text(preset.title).tag(Optional(preset.id))
                    }
                }
                .pickerStyle(.menu)

                Button {
                    if store.focusModeEnabled {
                        store.setFocusedProvider(nil)
                    } else if let selectedProviderID = chrome.selectedProviderID {
                        store.setFocusedProvider(selectedProviderID)
                    } else {
                        store.toggleFocusMode()
                    }
                } label: {
                    Label(store.focusModeEnabled ? "Compare Visible Providers" : "Focus Selected Provider", systemImage: store.focusModeEnabled ? "square.split.2x1" : "scope")
                }

                Button {
                    NotificationCenter.default.post(name: .councilEqualizePanes, object: nil)
                } label: {
                    Label("Equalize Pane Widths", systemImage: "equal.square")
                }

                Button {
                    store.requestNewChatOnAllTargets()
                } label: {
                    Label("Start New Chat", systemImage: "square.and.pencil")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var selectedProviderSection: some View {
        if let selectedProviderID = chrome.selectedProviderID,
           let provider = store.definition(for: selectedProviderID)
        {
            let paneState = store.state(for: selectedProviderID)
            inspectorSection("Selected Provider") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(provider.displayName)
                        .font(CouncilTypography.sectionTitle)

                    Text(paneState.lastPageTitle ?? paneState.automationState.message)
                        .font(CouncilTypography.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Include in Send", isOn: Binding(
                        get: { paneState.isIncludedInSend },
                        set: { store.setIncludedInSend(selectedProviderID, isIncluded: $0) }
                    ))

                    Toggle("Visible in Compare", isOn: Binding(
                        get: { paneState.isVisible },
                        set: { store.setPaneVisibility(selectedProviderID, isVisible: $0) }
                    ))
                }
            }
        }
    }

    private var sessionsSection: some View {
        inspectorSection("Saved Sessions") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Session name", text: $sessionName)
                        .textFieldStyle(.roundedBorder)

                    Button("Save") {
                        let trimmed = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            return
                        }
                        _ = store.saveCurrentSession(named: trimmed)
                        sessionName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }

                if store.savedSessions.isEmpty {
                    Text("No saved sessions yet.")
                        .font(CouncilTypography.meta)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.savedSessions.prefix(4)) { session in
                        Button {
                            guard store.applySavedSession(session.id) else {
                                return
                            }
                            NotificationCenter.default.post(name: .councilRestoreSession, object: session)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.name)
                                        .font(CouncilTypography.detail)
                                    Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(CouncilTypography.meta)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var preferencesSection: some View {
        inspectorSection("Preferences") {
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
        }
    }

    private var selectedLayoutPresetID: LayoutPresetID? {
        let visibleProviderIDs = store.orderedVisibleProviders.map(\.id)
        return store.layoutPresets.first(where: {
            $0.visibleProviderIDs == visibleProviderIDs && $0.focusedProviderID == store.focusedProviderID
        })?.id
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(CouncilTypography.meta)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CouncilMetrics.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CouncilMetrics.cardCornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(store: WorkspaceStore(), adapters: ProviderAdapterRegistry.adapters)
    }
}
