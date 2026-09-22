//
//  WebViewPane.swift
//  LLM Council
//
//

import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
enum WebJavaScriptBridge {
    static func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            asyncFunctionBody(for: script),
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    static func asyncFunctionBody(for script: String) -> String {
        var expression = script.trimmingCharacters(in: .whitespacesAndNewlines)
        while expression.last == ";" {
            expression.removeLast()
            expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "return await (\n\(expression)\n);"
    }
}

@MainActor
final class WebViewHub: ObservableObject, CouncilProviderClient {
    private static let supportedURLSchemes: Set<String> = ["http", "https"]

    private var webViews: [ProviderID: WKWebView] = [:]
    private var adapters: [ProviderID: any ProviderAutomationAdapter] = [:]
    private var currentZoom = 1.0

    func configure(adapters: [ProviderID: any ProviderAutomationAdapter]) {
        self.adapters = adapters
    }

    func register(providerID: ProviderID, webView: WKWebView) {
        webViews[providerID] = webView
        webView.pageZoom = currentZoom
    }

    func cachedWebView(providerID: ProviderID) -> WKWebView? {
        webViews[providerID]
    }

    func waitForMountedProviders(_ providerIDs: [ProviderID], timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if providerIDs.allSatisfy({ webViews[$0] != nil }) { return true }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return providerIDs.allSatisfy { webViews[$0] != nil }
    }

    func goBack(providerID: ProviderID) {
        webViews[providerID]?.goBack()
    }

    func goForward(providerID: ProviderID) {
        webViews[providerID]?.goForward()
    }

    func reload(providerID: ProviderID) {
        webViews[providerID]?.reload()
    }

    @discardableResult
    func openHome(providerID: ProviderID) -> Bool {
        loadIntoMountedWebView(
            providerID: providerID,
            preferredURL: providerURL(for: providerID)?.homeURL,
            fallbackToHome: false
        )
    }

    @discardableResult
    func openNewChat(providerID: ProviderID) -> Bool {
        loadIntoMountedWebView(
            providerID: providerID,
            preferredURL: providerURL(for: providerID)?.newChatURL,
            fallbackToHome: true
        )
    }

    @discardableResult
    func openURL(providerID: ProviderID, url: URL, fallbackToHome: Bool = true) -> Bool {
        loadIntoMountedWebView(
            providerID: providerID,
            preferredURL: sanitizedURL(from: url, for: providerID),
            fallbackToHome: fallbackToHome
        )
    }

    @discardableResult
    func openURL(providerID: ProviderID, urlString: String?, fallbackToHome: Bool = true) -> Bool {
        loadIntoMountedWebView(
            providerID: providerID,
            preferredURL: sanitizedURL(from: urlString, for: providerID),
            fallbackToHome: fallbackToHome
        )
    }

    @discardableResult
    func openRestoredChat(providerID: ProviderID, restoredURLString: String?) -> Bool {
        openURL(providerID: providerID, urlString: restoredURLString, fallbackToHome: true)
    }

    @discardableResult
    private func loadIntoMountedWebView(
        providerID: ProviderID,
        preferredURL: URL?,
        fallbackToHome: Bool
    ) -> Bool {
        guard
            let webView = webViews[providerID],
            let definition = providerURL(for: providerID)
        else {
            return false
        }

        let targetURL = preferredURL ?? (fallbackToHome ? definition.homeURL : nil)
        guard let targetURL else {
            return false
        }

        webView.load(URLRequest(url: targetURL))
        return true
    }

    private func providerURL(for providerID: ProviderID) -> ProviderDefinition? {
        BuiltInProviders.byID[providerID]
    }

    private func sanitizedURL(from urlString: String?, for providerID: ProviderID) -> URL? {
        guard let rawValue = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              Self.supportedURLSchemes.contains(scheme),
              let url = components.url,
              let host = url.host?.lowercased(),
              !host.isEmpty,
              isHostAllowed(host, for: providerID)
        else {
            return nil
        }
        return url
    }

    private func sanitizedURL(from url: URL, for providerID: ProviderID) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              Self.supportedURLSchemes.contains(scheme),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              isHostAllowed(host, for: providerID)
        else {
            return nil
        }
        return url
    }

    private func isHostAllowed(_ host: String, for providerID: ProviderID) -> Bool {
        for allowed in allowedHosts(for: providerID) {
            if host == allowed || host.hasSuffix(".\(allowed)") {
                return true
            }
        }
        return false
    }

    private func allowedHosts(for providerID: ProviderID) -> [String] {
        switch providerID {
        case .chatGPT:
            return ["chatgpt.com"]
        case .claude:
            return ["claude.ai"]
        case .gemini:
            return ["gemini.google.com"]
        case .grok:
            return ["grok.com"]
        case .perplexity:
            return ["perplexity.ai"]
        case .deepSeek:
            return ["chat.deepseek.com", "deepseek.com"]
        }
    }

    func sendPrompt(
        _ prompt: String,
        to providerIDs: [ProviderID],
        using adapters: [ProviderID: any ProviderAutomationAdapter],
        completion: @escaping ([WebAutomationResult]) -> Void
    ) {
        configure(adapters: adapters)
        guard !providerIDs.isEmpty else {
            completion([])
            return
        }

        Task { @MainActor in
            let tasks = providerIDs.map { providerID in
                Task { @MainActor in
                    do {
                        _ = try await self.submit(prompt, to: providerID)
                        return WebAutomationResult(providerID: providerID, success: true, message: "Sent")
                    } catch {
                        return WebAutomationResult(
                            providerID: providerID,
                            success: false,
                            message: error.localizedDescription
                        )
                    }
                }
            }
            var results: [WebAutomationResult] = []
            for task in tasks {
                results.append(await task.value)
            }
            completion(results)
        }
    }

    func submit(_ message: String, to providerID: ProviderID) async throws -> ProviderSubmissionReceipt {
        let webView = try requiredWebView(for: providerID)
        let adapter = try requiredAdapter(for: providerID)
        let baseline = try await completionProbe(providerID: providerID, webView: webView, adapter: adapter)
        let value = try await evaluate(adapter.makeSubmitScript(message: message), in: webView)

        guard let dictionary = value as? [String: Any],
              let ok = dictionary["ok"] as? Bool,
              ok,
              let submissionToken = dictionary["submissionToken"] as? String,
              !submissionToken.isEmpty
        else {
            let message = (value as? [String: Any])?["error"] as? String ?? "send-not-confirmed"
            if message == "composer-prompt-mismatch" || message == "submitted-prompt-mismatch" {
                throw CouncilProviderClientError.submittedPromptMismatch(providerID)
            }
            throw CouncilProviderClientError.submissionFailed(providerID, message)
        }

        return ProviderSubmissionReceipt(
            providerID: providerID,
            baselineResponseCount: baseline.responseCount,
            baselineResponseText: baseline.text,
            baselineResponseFingerprints: baseline.responseFingerprints,
            submissionToken: submissionToken,
            expectedPromptText: message,
            promptConfirmationRequired: dictionary["promptConfirmationRequired"] as? Bool ?? false,
            submittedAt: .now
        )
    }

    func waitForCompletion(
        from receipt: ProviderSubmissionReceipt,
        timeout: TimeInterval
    ) async throws -> String {
        let webView = try requiredWebView(for: receipt.providerID)
        let adapter = try requiredAdapter(for: receipt.providerID)
        let deadline = Date().addingTimeInterval(timeout)
        var lastCandidate = ""
        var stableProbeCount = 0

        while Date() < deadline {
            try Task.checkCancellation()
            let probe = try await completionProbe(
                providerID: receipt.providerID,
                webView: webView,
                adapter: adapter
            )

            if probe.rateLimited {
                throw CouncilProviderClientError.rateLimited(
                    receipt.providerID,
                    probe.rateLimitMessage.isEmpty ? "provider usage limit" : probe.rateLimitMessage
                )
            }

            let submittedPromptMatches = !receipt.promptConfirmationRequired
                || normalizedPromptText(probe.latestSubmittedPrompt) == normalizedPromptText(receipt.expectedPromptText)
            if receipt.promptConfirmationRequired,
               !probe.latestSubmittedPrompt.isEmpty,
               !submittedPromptMatches
            {
                throw CouncilProviderClientError.submittedPromptMismatch(receipt.providerID)
            }

            let isNewResponse = !probe.latestFingerprint.isEmpty
                && probe.latestBaselineToken != receipt.submissionToken
                && !receipt.baselineResponseFingerprints.contains(probe.latestFingerprint)
            let responseBelongsToSubmittedPrompt = !receipt.promptConfirmationRequired
                || probe.responseFollowsSubmittedPrompt
            if submittedPromptMatches,
               responseBelongsToSubmittedPrompt,
               isNewResponse,
               !probe.isStreaming,
               !probe.text.isEmpty
            {
                if probe.text == lastCandidate {
                    stableProbeCount += 1
                } else {
                    lastCandidate = probe.text
                    stableProbeCount = 1
                }
                if stableProbeCount >= 2 {
                    return probe.text
                }
            } else {
                stableProbeCount = 0
            }

            try await Task.sleep(for: .milliseconds(750))
        }

        throw CouncilProviderClientError.timedOut(receipt.providerID)
    }

    func extractLatestResponse(from providerID: ProviderID) async throws -> String {
        let webView = try requiredWebView(for: providerID)
        let adapter = try requiredAdapter(for: providerID)
        let probe = try await completionProbe(providerID: providerID, webView: webView, adapter: adapter)
        guard !probe.text.isEmpty else {
            throw CouncilProviderClientError.extractionFailed(providerID)
        }
        return probe.text
    }

    func startNewConversation(for providerID: ProviderID) async throws {
        guard let webView = webViews[providerID],
              let definition = providerURL(for: providerID),
              webView.load(URLRequest(url: definition.newChatURL)) != nil
        else {
            throw CouncilProviderClientError.webViewUnavailable(providerID)
        }
        try await waitUntilReady(providerID, timeout: 30, requireNavigationCycle: true)

        let adapter = try requiredAdapter(for: providerID)
        var blankProbeCount = 0
        while blankProbeCount < 3 {
            let probe = try await completionProbe(providerID: providerID, webView: webView, adapter: adapter)
            let existingMessageCount = probe.responseCount + probe.submittedPromptCount
            guard existingMessageCount == 0 else {
                throw CouncilProviderClientError.freshConversationNotEmpty(providerID, existingMessageCount)
            }
            blankProbeCount += 1
            if blankProbeCount < 3 {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func isAuthenticated(_ providerID: ProviderID) async -> Bool {
        guard let webView = webViews[providerID], let adapter = adapters[providerID] else { return false }
        do {
            let value = try await evaluate(adapter.makeAuthenticationProbeScript(), in: webView)
            return (value as? [String: Any])?["authenticated"] as? Bool ?? false
        } catch {
            return false
        }
    }

    func recoverFromFailure(for providerID: ProviderID) async throws {
        let webView = try requiredWebView(for: providerID)
        let adapter = try requiredAdapter(for: providerID)
        do {
            _ = try await evaluate(adapter.makeRecoveryScript(), in: webView)
            webView.reload()
            try await waitUntilReady(providerID, timeout: 30, requireNavigationCycle: true)
        } catch {
            throw CouncilProviderClientError.recoveryFailed(providerID, error.localizedDescription)
        }
    }

    private func waitUntilReady(
        _ providerID: ProviderID,
        timeout: TimeInterval,
        requireNavigationCycle: Bool = false
    ) async throws {
        guard let webView = webViews[providerID] else {
            throw CouncilProviderClientError.webViewUnavailable(providerID)
        }
        let deadline = Date().addingTimeInterval(timeout)
        var observedNavigation = !requireNavigationCycle
        while Date() < deadline {
            try Task.checkCancellation()
            if webView.isLoading || webView.estimatedProgress < 0.99 {
                observedNavigation = true
            }
            if observedNavigation,
               !webView.isLoading,
               webView.estimatedProgress >= 0.99,
               await isAuthenticated(providerID)
            {
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw CouncilProviderClientError.unauthenticated(providerID)
    }

    private func completionProbe(
        providerID: ProviderID,
        webView: WKWebView,
        adapter: any ProviderAutomationAdapter
    ) async throws -> ProviderCompletionProbe {
        let value = try await evaluate(adapter.makeCompletionProbeScript(), in: webView)
        guard let dictionary = value as? [String: Any] else {
            throw CouncilProviderClientError.extractionFailed(providerID)
        }
        return ProviderCompletionProbe(
            responseCount: dictionary["responseCount"] as? Int ?? 0,
            responseFingerprints: Set(dictionary["responseFingerprints"] as? [String] ?? []),
            latestFingerprint: dictionary["latestFingerprint"] as? String ?? "",
            latestBaselineToken: dictionary["latestBaselineToken"] as? String ?? "",
            submittedPromptCount: dictionary["submittedPromptCount"] as? Int ?? 0,
            latestSubmittedPrompt: dictionary["latestSubmittedPrompt"] as? String ?? "",
            responseFollowsSubmittedPrompt: dictionary["responseFollowsSubmittedPrompt"] as? Bool ?? false,
            text: dictionary["text"] as? String ?? "",
            isStreaming: dictionary["isStreaming"] as? Bool ?? false,
            rateLimited: dictionary["rateLimited"] as? Bool ?? false,
            rateLimitMessage: dictionary["rateLimitMessage"] as? String ?? ""
        )
    }

    private func normalizedPromptText(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func requiredWebView(for providerID: ProviderID) throws -> WKWebView {
        guard let webView = webViews[providerID] else {
            throw CouncilProviderClientError.webViewUnavailable(providerID)
        }
        return webView
    }

    private func requiredAdapter(for providerID: ProviderID) throws -> any ProviderAutomationAdapter {
        guard let adapter = adapters[providerID] else {
            throw CouncilProviderClientError.adapterUnavailable(providerID)
        }
        return adapter
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await WebJavaScriptBridge.evaluate(script, in: webView)
    }

    func setGlobalZoom(_ zoom: Double) {
        currentZoom = zoom
        for webView in webViews.values {
            webView.pageZoom = zoom
        }
    }
}

private struct ProviderCompletionProbe {
    let responseCount: Int
    let responseFingerprints: Set<String>
    let latestFingerprint: String
    let latestBaselineToken: String
    let submittedPromptCount: Int
    let latestSubmittedPrompt: String
    let responseFollowsSubmittedPrompt: Bool
    let text: String
    let isStreaming: Bool
    let rateLimited: Bool
    let rateLimitMessage: String
}

struct WebViewPane: NSViewRepresentable {
    let provider: ProviderDefinition
    let adapter: any ProviderAutomationAdapter
    @Binding var paneState: ProviderPaneState
    let hub: WebViewHub

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        if let cached = hub.cachedWebView(providerID: provider.id) {
            context.coordinator.webView = cached
            cached.navigationDelegate = context.coordinator
            cached.uiDelegate = context.coordinator
            return cached
        }

        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = websiteDataStore(for: provider.id)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        context.coordinator.webView = webView
        hub.register(providerID: provider.id, webView: webView)
        _ = hub.openRestoredChat(providerID: provider.id, restoredURLString: paneState.lastKnownURLString)
        return webView
    }

    func updateNSView(_: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator _: Coordinator) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private func websiteDataStore(for providerID: ProviderID) -> WKWebsiteDataStore {
        if #available(macOS 14.0, *) {
            return WKWebsiteDataStore(forIdentifier: dataStoreID(for: providerID))
        }
        return .default()
    }

    private func dataStoreID(for providerID: ProviderID) -> UUID {
        switch providerID {
        case .chatGPT:
            return UUID(uuidString: "1977A93E-6449-4D56-8C52-120E1E929001")!
        case .claude:
            return UUID(uuidString: "1977A93E-6449-4D56-8C52-120E1E929002")!
        case .gemini:
            return UUID(uuidString: "1977A93E-6449-4D56-8C52-120E1E929003")!
        case .grok:
            return UUID(uuidString: "1977A93E-6449-4D56-8C52-120E1E929004")!
        case .perplexity:
            return UUID(uuidString: "1977A93E-6449-4D56-8C52-120E1E929005")!
        case .deepSeek:
            return UUID(uuidString: "1977A93E-6449-4D56-8C52-120E1E929006")!
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewPane
        weak var webView: WKWebView?

        init(_ parent: WebViewPane) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            parent.paneState.estimatedProgress = webView.estimatedProgress
            updateNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            parent.paneState.estimatedProgress = 1
            parent.paneState.automationState = ProviderAutomationState(level: .ready, message: "Ready", updatedAt: .now)
            updateNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            parent.paneState.automationState = ProviderAutomationState(
                level: .failed,
                message: "Navigation failed: \(error.localizedDescription)",
                updatedAt: .now
            )
            updateNavigationState(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation _: WKNavigation!,
            withError error: Error
        ) {
            parent.paneState.automationState = ProviderAutomationState(
                level: .failed,
                message: "Load failed: \(error.localizedDescription)",
                updatedAt: .now
            )
            updateNavigationState(from: webView)
        }

        func webView(
            _: WKWebView,
            createWebViewWith _: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
                return nil
            }
            NSWorkspace.shared.open(url)
            return nil
        }

        private func updateNavigationState(from webView: WKWebView) {
            parent.paneState.lastKnownURLString = webView.url?.absoluteString
            parent.paneState.lastPageTitle = webView.title
            parent.paneState.canGoBack = webView.canGoBack
            parent.paneState.canGoForward = webView.canGoForward
            parent.paneState.estimatedProgress = webView.estimatedProgress
        }
    }
}
