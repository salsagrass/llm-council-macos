//
//  CouncilModels.swift
//  LLM Council
//
//

import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case chatGPT = "chatgpt"
    case claude
    case gemini
    case grok
    case perplexity
    case deepSeek = "deepseek"

    var id: String {
        rawValue
    }
}

struct ProviderDefinition: Codable, Hashable, Identifiable {
    let id: ProviderID
    let displayName: String
    let homeURL: URL
    let newChatURL: URL
    let defaultVisible: Bool
}

enum BuiltInProviders {
    static let definitions: [ProviderDefinition] = [
        ProviderDefinition(
            id: .chatGPT,
            displayName: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!,
            newChatURL: URL(string: "https://chatgpt.com/")!,
            defaultVisible: true
        ),
        ProviderDefinition(
            id: .claude,
            displayName: "Claude",
            homeURL: URL(string: "https://claude.ai/")!,
            newChatURL: URL(string: "https://claude.ai/new")!,
            defaultVisible: true
        ),
        ProviderDefinition(
            id: .gemini,
            displayName: "Gemini",
            homeURL: URL(string: "https://gemini.google.com/")!,
            newChatURL: URL(string: "https://gemini.google.com/")!,
            defaultVisible: true
        ),
        ProviderDefinition(
            id: .grok,
            displayName: "Grok",
            homeURL: URL(string: "https://grok.com/c")!,
            newChatURL: URL(string: "https://grok.com/c")!,
            defaultVisible: false
        ),
        ProviderDefinition(
            id: .perplexity,
            displayName: "Perplexity",
            homeURL: URL(string: "https://www.perplexity.ai/")!,
            newChatURL: URL(string: "https://www.perplexity.ai/")!,
            defaultVisible: false
        ),
        ProviderDefinition(
            id: .deepSeek,
            displayName: "DeepSeek",
            homeURL: URL(string: "https://chat.deepseek.com/")!,
            newChatURL: URL(string: "https://chat.deepseek.com/")!,
            defaultVisible: false
        ),
    ]

    static let byID: [ProviderID: ProviderDefinition] = Dictionary(
        uniqueKeysWithValues: definitions.map { ($0.id, $0) }
    )
}

enum AutomationStateLevel: String, Codable, Hashable {
    case idle
    case ready
    case running
    case failed
}

struct ProviderAutomationState: Codable, Hashable {
    var level: AutomationStateLevel
    var message: String
    var updatedAt: Date

    static let idle = ProviderAutomationState(level: .idle, message: "Idle", updatedAt: .distantPast)
}

struct ProviderPaneState: Codable, Hashable {
    let providerID: ProviderID
    var isVisible: Bool
    var isIncludedInSend: Bool
    var lastKnownURLString: String?
    var lastPageTitle: String?
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool
    var automationState: ProviderAutomationState

    static func initialState(for providerID: ProviderID, visible: Bool = true) -> ProviderPaneState {
        ProviderPaneState(
            providerID: providerID,
            isVisible: visible,
            isIncludedInSend: visible,
            lastKnownURLString: nil,
            lastPageTitle: nil,
            estimatedProgress: 0,
            canGoBack: false,
            canGoForward: false,
            automationState: .idle
        )
    }
}

enum PromptDispatchPhase: String, Codable, Hashable {
    case idle
    case bootstrapping
    case sending
    case succeeded
    case failed
    case cancelled
}

struct PromptDispatchState: Codable, Hashable {
    var phase: PromptDispatchPhase
    var message: String
    var targetProviderIDs: [ProviderID]
    var successfulProviderIDs: [ProviderID]
    var failedProviderIDs: [ProviderID]
    var lastPrompt: String?
    var lastUpdatedAt: Date

    static let idle = PromptDispatchState(
        phase: .idle,
        message: "Ready",
        targetProviderIDs: [],
        successfulProviderIDs: [],
        failedProviderIDs: [],
        lastPrompt: nil,
        lastUpdatedAt: .distantPast
    )

    var isActive: Bool {
        phase == .bootstrapping || phase == .sending
    }
}

enum ComposerSendScope: String, Codable, CaseIterable, Hashable {
    case allVisible
    case includedOnly
}

enum LayoutPresetID: String, Codable, CaseIterable, Hashable, Identifiable {
    case allProviders
    case analysisPair
    case writingFocus

    var id: String {
        rawValue
    }
}

struct WorkspaceLayoutPreset: Codable, Hashable, Identifiable {
    let id: LayoutPresetID
    let title: String
    let visibleProviderIDs: [ProviderID]
    let focusedProviderID: ProviderID?
}

enum BuiltInLayoutPresets {
    static let all: [WorkspaceLayoutPreset] = [
        WorkspaceLayoutPreset(
            id: .allProviders,
            title: "All Providers",
            visibleProviderIDs: ProviderID.allCases,
            focusedProviderID: nil
        ),
        WorkspaceLayoutPreset(
            id: .analysisPair,
            title: "Analysis Pair",
            visibleProviderIDs: [.chatGPT, .claude],
            focusedProviderID: nil
        ),
        WorkspaceLayoutPreset(
            id: .writingFocus,
            title: "Writing Focus",
            visibleProviderIDs: [.chatGPT, .claude, .gemini],
            focusedProviderID: .chatGPT
        ),
    ]
}

struct PromptHistoryEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

struct PromptPreset: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var prompt: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, prompt: String, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.updatedAt = updatedAt
    }
}

struct WorkspaceSnapshot: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var pageZoom: Double
    var paneStates: [ProviderPaneState]
    var paneOrder: [ProviderID]
    var focusedProviderID: ProviderID?
    var sendScope: ComposerSendScope
    var clearComposerAfterSend: Bool
    var promptHistory: [PromptHistoryEntry]
    var promptPresets: [PromptPreset]
    var savedSessions: [SavedWorkspaceSession]

    init(
        schemaVersion: Int,
        pageZoom: Double,
        paneStates: [ProviderPaneState],
        paneOrder: [ProviderID],
        focusedProviderID: ProviderID?,
        sendScope: ComposerSendScope,
        clearComposerAfterSend: Bool,
        promptHistory: [PromptHistoryEntry],
        promptPresets: [PromptPreset],
        savedSessions: [SavedWorkspaceSession]
    ) {
        self.schemaVersion = schemaVersion
        self.pageZoom = pageZoom
        self.paneStates = paneStates
        self.paneOrder = paneOrder
        self.focusedProviderID = focusedProviderID
        self.sendScope = sendScope
        self.clearComposerAfterSend = clearComposerAfterSend
        self.promptHistory = promptHistory
        self.promptPresets = promptPresets
        self.savedSessions = savedSessions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case pageZoom
        case paneStates
        case paneOrder
        case focusedProviderID
        case sendScope
        case clearComposerAfterSend
        case promptHistory
        case promptPresets
        case savedSessions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? WorkspaceSnapshot.currentSchemaVersion
        pageZoom = try container.decodeIfPresent(Double.self, forKey: .pageZoom) ?? 1.0
        paneStates = try container.decodeIfPresent([ProviderPaneState].self, forKey: .paneStates) ?? []
        paneOrder = try container.decodeIfPresent([ProviderID].self, forKey: .paneOrder) ?? paneStates.map(\.providerID)
        focusedProviderID = try container.decodeIfPresent(ProviderID.self, forKey: .focusedProviderID)
        sendScope = try container.decodeIfPresent(ComposerSendScope.self, forKey: .sendScope) ?? .allVisible
        clearComposerAfterSend = try container.decodeIfPresent(Bool.self, forKey: .clearComposerAfterSend) ?? true
        promptHistory = try container.decodeIfPresent([PromptHistoryEntry].self, forKey: .promptHistory) ?? []
        promptPresets = try container.decodeIfPresent([PromptPreset].self, forKey: .promptPresets) ?? []
        savedSessions = try container.decodeIfPresent([SavedWorkspaceSession].self, forKey: .savedSessions) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(pageZoom, forKey: .pageZoom)
        try container.encode(paneStates, forKey: .paneStates)
        try container.encode(paneOrder, forKey: .paneOrder)
        try container.encodeIfPresent(focusedProviderID, forKey: .focusedProviderID)
        try container.encode(sendScope, forKey: .sendScope)
        try container.encode(clearComposerAfterSend, forKey: .clearComposerAfterSend)
        try container.encode(promptHistory, forKey: .promptHistory)
        try container.encode(promptPresets, forKey: .promptPresets)
        try container.encode(savedSessions, forKey: .savedSessions)
    }
}

struct SavedWorkspaceSession: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var focusedProviderID: ProviderID?
    var visibleProviderIDs: [ProviderID]
    var includedInSendProviderIDs: [ProviderID]
    var paneOrder: [ProviderID]
    var composerDraft: String
    var providerChatURLs: [ProviderID: String]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        focusedProviderID: ProviderID?,
        visibleProviderIDs: [ProviderID],
        includedInSendProviderIDs: [ProviderID]? = nil,
        paneOrder: [ProviderID],
        composerDraft: String,
        providerChatURLs: [ProviderID: String]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.focusedProviderID = focusedProviderID
        self.visibleProviderIDs = visibleProviderIDs
        self.includedInSendProviderIDs = includedInSendProviderIDs ?? visibleProviderIDs
        self.paneOrder = paneOrder
        self.composerDraft = composerDraft
        self.providerChatURLs = providerChatURLs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case updatedAt
        case focusedProviderID
        case visibleProviderIDs
        case includedInSendProviderIDs
        case paneOrder
        case composerDraft
        case providerChatURLs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Saved Session"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        focusedProviderID = try container.decodeIfPresent(ProviderID.self, forKey: .focusedProviderID)
        visibleProviderIDs = try container.decodeIfPresent([ProviderID].self, forKey: .visibleProviderIDs) ?? []
        includedInSendProviderIDs =
            try container.decodeIfPresent([ProviderID].self, forKey: .includedInSendProviderIDs) ?? visibleProviderIDs
        paneOrder = try container.decodeIfPresent([ProviderID].self, forKey: .paneOrder) ?? visibleProviderIDs
        composerDraft = try container.decodeIfPresent(String.self, forKey: .composerDraft) ?? ""
        providerChatURLs = try container.decodeIfPresent([ProviderID: String].self, forKey: .providerChatURLs) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(focusedProviderID, forKey: .focusedProviderID)
        try container.encode(visibleProviderIDs, forKey: .visibleProviderIDs)
        try container.encode(includedInSendProviderIDs, forKey: .includedInSendProviderIDs)
        try container.encode(paneOrder, forKey: .paneOrder)
        try container.encode(composerDraft, forKey: .composerDraft)
        try container.encode(providerChatURLs, forKey: .providerChatURLs)
    }
}

protocol WorkspacePersisting {
    func load() -> WorkspaceSnapshot?
    func save(_ snapshot: WorkspaceSnapshot)
}

protocol ProviderAutomationAdapter {
    var providerID: ProviderID { get }
    func makeSubmitScript(message: String) -> String
    func makeCompletionProbeScript() -> String
    func makeAuthenticationProbeScript() -> String
    func makeRecoveryScript() -> String
}

struct WebAutomationResult {
    let providerID: ProviderID
    let success: Bool
    let message: String
}
