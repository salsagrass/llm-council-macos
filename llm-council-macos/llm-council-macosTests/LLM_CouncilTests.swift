//
//  LLM_CouncilTests.swift
//  LLM CouncilTests
//
//

import AppKit
import Foundation
@testable import LLM_Council
import Testing
import WebKit

struct LLM_CouncilTests {
    @MainActor
    @Test("Composer focus updates preserve direct clicks and honor explicit requests")
    func composerFocusDoesNotGetClearedAfterClick() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let scrollView = NSTextView.scrollableTextView()
        window.contentView = scrollView
        let textView = try #require(scrollView.documentView as? NSTextView)

        #expect(window.makeFirstResponder(textView))
        CouncilComposerTextView.applyFocusRequest(false, to: textView)
        #expect(window.firstResponder === textView)

        window.makeFirstResponder(nil)
        CouncilComposerTextView.applyFocusRequest(true, to: textView)
        #expect(window.firstResponder === textView)
    }

    @MainActor
    @Test("WebKit bridge awaits Promise results and returns serializable values")
    func webKitBridgeAwaitsPromiseResults() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let navigationWaiter = WebViewNavigationWaiter()
        try await navigationWaiter.load("<html><body>ready</body></html>", in: webView)

        let value = try await WebJavaScriptBridge.evaluate(
            """
            (async function() {
              await new Promise((resolve) => setTimeout(resolve, 10));
              return { ok: true, method: "promise" };
            })();
            """,
            in: webView
        )
        let result = try #require(value as? [String: Any])
        #expect(result["ok"] as? Bool == true)
        #expect(result["method"] as? String == "promise")
    }

    @MainActor
    @Test("ChatGPT submission waits for and confirms the current prompt")
    func chatGPTSubmissionDoesNotReusePreviousComposerState() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let navigationWaiter = WebViewNavigationWaiter()
        try await navigationWaiter.load(
            """
            <html><head><style>
              #prompt-textarea { min-height: 80px; }
              button { width: 80px; height: 30px; }
            </style></head><body>
              <div id="prompt-textarea" contenteditable="true"><p>Previous council prompt</p></div>
              <button data-testid="send-button">Send</button>
              <div id="messages"></div>
              <script>
                const composer = document.getElementById("prompt-textarea");
                let editorState = composer.innerText;
                composer.addEventListener("input", () => {
                  const nextValue = composer.innerText;
                  setTimeout(() => { editorState = nextValue; }, 150);
                });
                document.querySelector("button").addEventListener("click", () => {
                  const message = document.createElement("div");
                  message.setAttribute("data-message-author-role", "user");
                  message.textContent = editorState;
                  document.getElementById("messages").appendChild(message);
                });
              </script>
            </body></html>
            """,
            in: webView
        )

        let expectedPrompt = "Current council prompt\n\nwith a second paragraph"
        let adapter = try #require(ProviderAdapterRegistry.adapter(for: .chatGPT))
        let value = try await WebJavaScriptBridge.evaluate(
            adapter.makeSubmitScript(message: expectedPrompt),
            in: webView
        )
        let result = try #require(value as? [String: Any])
        let submittedPrompt = try await WebJavaScriptBridge.evaluate(
            """
            (function() {
              return document.querySelector("[data-message-author-role='user']")?.innerText || "";
            })();
            """,
            in: webView
        )

        #expect(result["ok"] as? Bool == true)
        #expect(result["promptConfirmationRequired"] as? Bool == true)
        #expect((submittedPrompt as? String)?.contains("Current council prompt") == true)
        #expect((submittedPrompt as? String)?.contains("Previous council prompt") == false)
    }

    @MainActor
    @Test("Completion probe selects the newest response content in DOM order")
    func completionProbeRejectsWrapperLabelsAndStaleContent() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let navigationWaiter = WebViewNavigationWaiter()
        try await navigationWaiter.load(
            """
            <html><body>
              <model-response id="old-response">
                <div class="model-response-text">Old answer from another turn</div>
              </model-response>
              <model-response id="current-response">
                <span>Gemini said</span>
                <div class="model-response-text">Current answer only</div>
              </model-response>
            </body></html>
            """,
            in: webView
        )
        let adapter = try #require(ProviderAdapterRegistry.adapter(for: .gemini))
        let value = try await WebJavaScriptBridge.evaluate(
            adapter.makeCompletionProbeScript(),
            in: webView
        )
        let result = try #require(value as? [String: Any])

        #expect(result["text"] as? String == "Current answer only")
        #expect((result["latestFingerprint"] as? String)?.isEmpty == false)
        #expect((result["responseFingerprints"] as? [String])?.isEmpty == false)
    }

    @MainActor
    @Test("ChatGPT completion must follow the prompt from the current run")
    func chatGPTCompletionIsOrderedAfterCurrentPrompt() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let navigationWaiter = WebViewNavigationWaiter()
        try await navigationWaiter.load(
            """
            <html><body>
              <div data-message-author-role="user">Previous prompt</div>
              <div data-message-author-role="assistant">Previous response</div>
              <div data-message-author-role="user">Current prompt</div>
            </body></html>
            """,
            in: webView
        )
        let adapter = try #require(ProviderAdapterRegistry.adapter(for: .chatGPT))
        let beforeValue = try await WebJavaScriptBridge.evaluate(
            adapter.makeCompletionProbeScript(),
            in: webView
        )
        let before = try #require(beforeValue as? [String: Any])
        #expect(before["responseFollowsSubmittedPrompt"] as? Bool == false)

        _ = try await WebJavaScriptBridge.evaluate(
            """
            (function() {
              const response = document.createElement("div");
              response.setAttribute("data-message-author-role", "assistant");
              response.textContent = "Current response";
              document.body.appendChild(response);
              return true;
            })();
            """,
            in: webView
        )
        let afterValue = try await WebJavaScriptBridge.evaluate(
            adapter.makeCompletionProbeScript(),
            in: webView
        )
        let after = try #require(afterValue as? [String: Any])
        #expect(after["responseFollowsSubmittedPrompt"] as? Bool == true)
        #expect(after["text"] as? String == "Current response")
    }

    @MainActor
    @Test("Built-in provider registry is stable")
    func builtInProviderRegistryContainsExpectedSix() {
        let ids = Set(BuiltInProviders.definitions.map(\.id))
        #expect(BuiltInProviders.definitions.count == 6)
        #expect(ids == Set([.chatGPT, .claude, .gemini, .grok, .perplexity, .deepSeek]))
    }

    @MainActor
    @Test("Layout preset visibility updates expected providers")
    func applyingPresetUpdatesVisibility() {
        let persistence = MemoryPersistence()
        let store = WorkspaceStore(persistence: persistence)
        store.applyLayoutPreset(.analysisPair)

        #expect(store.state(for: .chatGPT).isVisible)
        #expect(store.state(for: .claude).isVisible)
        #expect(store.state(for: .gemini).isVisible == false)
        #expect(store.state(for: .grok).isVisible == false)
        #expect(store.state(for: .perplexity).isVisible == false)
        #expect(store.state(for: .deepSeek).isVisible == false)
    }

    @MainActor
    @Test("Prompt history dedupes and caps at max entries")
    func historyDedupesAndCaps() {
        var history: [PromptHistoryEntry] = []
        for index in 1 ... 105 {
            history = WorkspaceStore.upsertHistory(history, prompt: "Prompt \(index)")
        }

        history = WorkspaceStore.upsertHistory(history, prompt: "Prompt 100")

        #expect(history.count == 100)
        #expect(history.first?.text == "Prompt 100")
        #expect(history.filter { $0.text == "Prompt 100" }.count == 1)
    }

    @MainActor
    @Test("Deleting one prompt history entry preserves remaining entries and persists")
    func deletingSingleHistoryEntryPersists() {
        let persistence = MemoryPersistence()
        let store = WorkspaceStore(persistence: persistence)

        store.updateComposer(with: "First prompt")
        _ = store.registerPromptSend(now: Date(timeIntervalSince1970: 1))
        store.updateComposer(with: "Second prompt")
        _ = store.registerPromptSend(now: Date(timeIntervalSince1970: 2))
        store.updateComposer(with: "Third prompt")
        _ = store.registerPromptSend(now: Date(timeIntervalSince1970: 3))

        let removedID = store.promptHistory[1].id
        store.deleteHistoryEntry(removedID)

        #expect(store.promptHistory.map(\.text) == ["Third prompt", "First prompt"])
        #expect(store.promptHistory.contains(where: { $0.id == removedID }) == false)

        let reloaded = WorkspaceStore(persistence: persistence)
        #expect(reloaded.promptHistory.map(\.text) == ["Third prompt", "First prompt"])
        #expect(reloaded.promptHistory.contains(where: { $0.id == removedID }) == false)
    }

    @MainActor
    @Test("Clearing prompt history removes all entries and persists")
    func clearingHistoryPersists() {
        let persistence = MemoryPersistence()
        let store = WorkspaceStore(persistence: persistence)

        store.updateComposer(with: "Alpha prompt")
        _ = store.registerPromptSend(now: Date(timeIntervalSince1970: 1))
        store.updateComposer(with: "Beta prompt")
        _ = store.registerPromptSend(now: Date(timeIntervalSince1970: 2))
        #expect(store.promptHistory.isEmpty == false)

        store.clearHistory()
        #expect(store.promptHistory.isEmpty)

        let reloaded = WorkspaceStore(persistence: persistence)
        #expect(reloaded.promptHistory.isEmpty)
    }

    @MainActor
    @Test("Page zoom clamps and resets")
    func pageZoomClampsAndResets() {
        let persistence = MemoryPersistence()
        let store = WorkspaceStore(persistence: persistence)

        for _ in 0 ..< 20 {
            store.zoomOut()
        }
        #expect(store.pageZoom == WorkspaceStore.minPageZoom)

        for _ in 0 ..< 20 {
            store.zoomIn()
        }
        #expect(store.pageZoom == WorkspaceStore.maxPageZoom)

        store.resetZoom()
        #expect(store.pageZoom == 1.0)
    }

    @MainActor
    @Test("Saved session round-trips and captures workspace fields")
    func savedSessionRoundTripCapturesWorkspaceState() {
        let persistence = MemoryPersistence()
        let store = WorkspaceStore(persistence: persistence)

        store.setPaneVisibility(.gemini, isVisible: false)
        store.setIncludedInSend(.chatGPT, isIncluded: false)
        store.setFocusedProvider(.claude)
        store.updateComposer(with: "  draft prompt  ")
        store.updateNavigationState(
            for: .chatGPT,
            url: URL(string: "https://chatgpt.com/c/123"),
            title: nil,
            estimatedProgress: 1,
            canGoBack: true,
            canGoForward: false
        )
        store.updateNavigationState(
            for: .claude,
            url: URL(string: "https://claude.ai/chat/abc"),
            title: nil,
            estimatedProgress: 1,
            canGoBack: false,
            canGoForward: false
        )

        let timestamp = Date(timeIntervalSince1970: 42)
        let saved = store.saveCurrentSession(named: " Morning Session ", now: timestamp)

        #expect(saved != nil)
        #expect(saved?.name == "Morning Session")
        #expect(saved?.visibleProviderIDs == [.chatGPT, .claude])
        #expect(saved?.includedInSendProviderIDs == [.claude])
        #expect(saved?.focusedProviderID == .claude)
        #expect(saved?.composerDraft == "  draft prompt  ")
        #expect(saved?.providerChatURLs[.chatGPT] == "https://chatgpt.com/c/123")
        #expect(saved?.providerChatURLs[.claude] == "https://claude.ai/chat/abc")

        let reloaded = WorkspaceStore(persistence: persistence)
        #expect(reloaded.savedSessions.count == 1)
        #expect(reloaded.savedSessions[0].name == "Morning Session")
        #expect(reloaded.savedSessions[0].includedInSendProviderIDs == [.claude])
        #expect(reloaded.savedSessions[0].providerChatURLs[.chatGPT] == "https://chatgpt.com/c/123")
    }

    @MainActor
    @Test("Applying saved session restores pane state, focus, composer draft, and URLs")
    func applyingSavedSessionRestoresState() throws {
        let persistence = MemoryPersistence()
        let savedSession = try SavedWorkspaceSession(
            id: #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
            name: "Focus Pair",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            focusedProviderID: .claude,
            visibleProviderIDs: [.claude, .chatGPT],
            includedInSendProviderIDs: [.chatGPT],
            paneOrder: [.claude, .chatGPT],
            composerDraft: "Carry this prompt forward",
            providerChatURLs: [
                .claude: "https://claude.ai/new",
                .chatGPT: "https://chatgpt.com/c/abc",
            ]
        )

        let defaultPaneStates = BuiltInProviders.definitions.map {
            ProviderPaneState.initialState(for: $0.id, visible: $0.defaultVisible)
        }
        persistence.save(
            WorkspaceSnapshot(
                schemaVersion: WorkspaceSnapshot.currentSchemaVersion,
                pageZoom: 1.0,
                paneStates: defaultPaneStates,
                paneOrder: BuiltInProviders.definitions.map(\.id),
                focusedProviderID: nil,
                sendScope: .allVisible,
                clearComposerAfterSend: true,
                promptHistory: [],
                promptPresets: [],
                savedSessions: [savedSession]
            )
        )

        let store = WorkspaceStore(persistence: persistence)
        #expect(store.applySavedSession(savedSession.id))

        #expect(store.paneOrder == [.claude, .chatGPT, .gemini, .grok, .perplexity, .deepSeek])
        #expect(store.state(for: .claude).isVisible)
        #expect(store.state(for: .chatGPT).isVisible)
        #expect(store.state(for: .claude).isIncludedInSend == false)
        #expect(store.state(for: .chatGPT).isIncludedInSend)
        #expect(store.state(for: .gemini).isVisible == false)
        #expect(store.focusedProviderID == .claude)
        #expect(store.composerText == "Carry this prompt forward")
        #expect(store.state(for: .claude).lastKnownURLString == "https://claude.ai/new")
        #expect(store.state(for: .chatGPT).lastKnownURLString == "https://chatgpt.com/c/abc")
        #expect(store.state(for: .gemini).lastKnownURLString == nil)
    }

    @MainActor
    @Test("Legacy saved session decode defaults included providers")
    func legacySavedSessionDecodeDefaultsIncludedProviders() throws {
        let json = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "name": "Legacy",
          "createdAt": 0,
          "updatedAt": 1,
          "focusedProviderID": "chatgpt",
          "visibleProviderIDs": ["chatgpt", "claude"],
          "paneOrder": ["chatgpt", "claude"],
          "composerDraft": "hello",
          "providerChatURLs": []
        }
        """

        let decoded = try JSONDecoder().decode(SavedWorkspaceSession.self, from: Data(json.utf8))
        #expect(decoded.visibleProviderIDs == [.chatGPT, .claude])
        #expect(decoded.includedInSendProviderIDs == [.chatGPT, .claude])
    }

    @MainActor
    @Test("Prompt dispatch lifecycle tracks bootstrap completion cancellation and reset")
    func promptDispatchLifecycleTracksSharedSendState() {
        let persistence = MemoryPersistence()
        let store = WorkspaceStore(persistence: persistence)
        let prompt = "Compare this shell redesign"
        let targets: [ProviderID] = [.chatGPT, .claude]

        store.beginPromptBootstrap(prompt: prompt, targets: targets, now: Date(timeIntervalSince1970: 10))
        #expect(store.dispatchState.phase == .bootstrapping)
        #expect(store.dispatchState.targetProviderIDs == targets)
        #expect(store.dispatchState.lastPrompt == prompt)

        store.beginPromptDispatch(prompt: prompt, targets: targets, now: Date(timeIntervalSince1970: 11))
        #expect(store.dispatchState.phase == .sending)
        #expect(store.dispatchState.isActive)

        let results = [
            WebAutomationResult(providerID: .chatGPT, success: true, message: "Sent"),
            WebAutomationResult(providerID: .claude, success: false, message: "Timed out"),
        ]
        store.completePromptDispatch(results: results, prompt: prompt, now: Date(timeIntervalSince1970: 12))
        #expect(store.dispatchState.phase == .failed)
        #expect(store.dispatchState.successfulProviderIDs == [.chatGPT])
        #expect(store.dispatchState.failedProviderIDs == [.claude])
        #expect(store.dispatchState.message.contains("1/2"))

        store.beginPromptDispatch(prompt: prompt, targets: targets, now: Date(timeIntervalSince1970: 13))
        store.cancelPromptDispatchTracking(now: Date(timeIntervalSince1970: 14))
        #expect(store.dispatchState.phase == .cancelled)
        #expect(store.dispatchState.message == "Dispatch tracking cancelled.")

        store.resetPromptDispatchState(now: Date(timeIntervalSince1970: 15))
        #expect(store.dispatchState.phase == .idle)
        #expect(store.dispatchState.targetProviderIDs.isEmpty)
    }

    @MainActor
    @Test("Dispatch providers respect included only send scope")
    func dispatchProvidersRespectIncludedOnlyScope() {
        let persistence = MemoryPersistence()
        let store = WorkspaceStore(persistence: persistence)

        store.sendScope = .includedOnly
        store.setIncludedInSend(.chatGPT, isIncluded: false)
        store.setPaneVisibility(.gemini, isVisible: false)

        #expect(store.dispatchProviderIDs == [.claude])
    }

    @Test("Shortcut guide stays aligned with Cmd+/ command binding")
    func shortcutGuideStaysAlignedWithCmdSlashBinding() throws {
        let showShortcutItem = CouncilShortcutGuide.sections
            .flatMap(\.shortcuts)
            .first(where: { $0.id == "show-shortcuts" })
        #expect(showShortcutItem?.keyCombination == ["Cmd", "/"])

        let testsFileURL = URL(fileURLWithPath: #filePath)
        let appFileURL = testsFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("llm-council-macos")
            .appendingPathComponent("LLM_CouncilApp.swift")
        let appSource = try String(contentsOf: appFileURL, encoding: .utf8)

        #expect(appSource.contains(#".keyboardShortcut("/", modifiers: [.command])"#))
    }

    @MainActor
    @Test("Workspace chrome state tracks activated providers and sidebar selection")
    func workspaceChromeStateTracksSelectionAndActivation() {
        let chrome = WorkspaceChromeState()
        let paneStates: [ProviderID: ProviderPaneState] = [
            .chatGPT: ProviderPaneState(
                providerID: .chatGPT,
                isVisible: true,
                isIncludedInSend: true,
                lastKnownURLString: "https://chatgpt.com/c/123",
                lastPageTitle: "Draft",
                estimatedProgress: 1,
                canGoBack: false,
                canGoForward: false,
                automationState: .idle
            ),
            .claude: ProviderPaneState.initialState(for: .claude),
        ]

        chrome.syncActivatedProviders(from: paneStates)
        #expect(chrome.isProviderActivated(.chatGPT))
        #expect(chrome.isProviderActivated(.claude) == false)

        chrome.selectProvider(.claude)
        #expect(chrome.selectedProviderID == .claude)
        #expect(chrome.sidebarSelection == .provider(.claude))

        chrome.selectWorkspace()
        #expect(chrome.selectedProviderID == nil)
        #expect(chrome.sidebarSelection == .workspace)
    }
}

@MainActor
private final class WebViewNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private final class MemoryPersistence: WorkspacePersisting, @unchecked Sendable {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var data: Data?

    func load() -> WorkspaceSnapshot? {
        guard let data else {
            return nil
        }
        return try? decoder.decode(WorkspaceSnapshot.self, from: data)
    }

    func save(_ snapshot: WorkspaceSnapshot) {
        data = try? encoder.encode(snapshot)
    }
}
