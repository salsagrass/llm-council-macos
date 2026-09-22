//
//  ProviderAdapters.swift
//  LLM Council
//

import Foundation

private struct ProviderDOMConfiguration {
    let inputSelectors: [String]
    let sendButtonSelectors: [String]
    let responseSelectors: [String]
    let streamingSelectors: [String]
    let loginSelectors: [String]
    let rateLimitPhrases: [String]
}

struct SelectorBasedProviderAdapter: ProviderAutomationAdapter {
    let providerID: ProviderID
    fileprivate let configuration: ProviderDOMConfiguration

    func makeSubmitScript(message: String) -> String {
        ProviderJavaScript.makeSubmitScript(
            message: message,
            inputSelectors: configuration.inputSelectors,
            sendButtonSelectors: configuration.sendButtonSelectors,
            responseSelectors: configuration.responseSelectors
        )
    }

    func makeCompletionProbeScript() -> String {
        ProviderJavaScript.makeCompletionProbeScript(
            responseSelectors: configuration.responseSelectors,
            streamingSelectors: configuration.streamingSelectors,
            rateLimitPhrases: configuration.rateLimitPhrases
        )
    }

    func makeAuthenticationProbeScript() -> String {
        ProviderJavaScript.makeAuthenticationProbeScript(
            inputSelectors: configuration.inputSelectors,
            loginSelectors: configuration.loginSelectors
        )
    }

    func makeRecoveryScript() -> String {
        ProviderJavaScript.makeRecoveryScript()
    }
}

enum ProviderAdapterRegistry {
    static let adapters: [ProviderID: any ProviderAutomationAdapter] = [
        .chatGPT: SelectorBasedProviderAdapter(
            providerID: .chatGPT,
            configuration: ProviderDOMConfiguration(
                inputSelectors: [
                    "#prompt-textarea",
                    "textarea[data-id='root']",
                    "textarea[placeholder*='Message']",
                    "[contenteditable='true'][data-virtualkeyboard]",
                    "textarea",
                ],
                sendButtonSelectors: [
                    "button[data-testid='send-button']",
                    "button[data-testid='fruitjuice-send-button']",
                    "button[aria-label*='Send']",
                    "button[type='submit']",
                ],
                responseSelectors: [
                    "[data-message-author-role='assistant']",
                    "article[data-testid^='conversation-turn-'] [data-message-author-role='assistant']",
                ],
                streamingSelectors: [
                    "button[data-testid='stop-button']",
                    "button[aria-label*='Stop generating']",
                    "button[aria-label*='stop generating']",
                ],
                loginSelectors: [
                    "a[href*='auth/login']",
                    "button[data-testid*='login']",
                ],
                rateLimitPhrases: [
                    "you've reached your limit",
                    "you have reached your limit",
                    "usage limit",
                    "too many requests",
                ]
            )
        ),
        .claude: SelectorBasedProviderAdapter(
            providerID: .claude,
            configuration: ProviderDOMConfiguration(
                inputSelectors: [
                    "div.ProseMirror",
                    "[contenteditable='true'][role='textbox']",
                    "[contenteditable='true']",
                ],
                sendButtonSelectors: [
                    "button[aria-label='Send Message']",
                    "button[aria-label*='Send']",
                    "button[data-testid*='send']",
                    "button[type='submit']",
                ],
                responseSelectors: [
                    "[data-testid='assistant-message']",
                    "[data-is-streaming]",
                    ".font-claude-response",
                    "div[data-test-render-count] .prose",
                ],
                streamingSelectors: [
                    "button[aria-label*='Stop']",
                    "button[data-testid*='stop']",
                    "[data-is-streaming='true']",
                ],
                loginSelectors: [
                    "a[href*='login']",
                    "button[data-testid*='login']",
                ],
                rateLimitPhrases: [
                    "you are out of messages",
                    "message limit",
                    "usage limit",
                    "rate limit",
                ]
            )
        ),
        .gemini: SelectorBasedProviderAdapter(
            providerID: .gemini,
            configuration: ProviderDOMConfiguration(
                inputSelectors: [
                    ".ql-editor[aria-label='Enter a prompt here']",
                    ".ql-editor",
                    "rich-textarea [contenteditable='true']",
                    "[contenteditable='true'][role='textbox']",
                    "textarea",
                ],
                sendButtonSelectors: [
                    "button[aria-label='Send message']",
                    "button[aria-label*='Send']",
                    "button.send-button",
                    "button[type='submit']",
                ],
                responseSelectors: [
                    "model-response .model-response-text",
                    "model-response message-content",
                    "model-response",
                    ".response-container-content",
                ],
                streamingSelectors: [
                    "button[aria-label*='Stop response']",
                    "button[aria-label*='Stop']",
                    ".response-container-content.loading",
                ],
                loginSelectors: [
                    "a[href*='accounts.google.com']",
                    "a[aria-label*='Sign in']",
                ],
                rateLimitPhrases: [
                    "you've reached your limit",
                    "you have reached your limit",
                    "rate limit",
                    "try again later",
                ]
            )
        ),
        .grok: genericAdapter(
            providerID: .grok,
            inputSelectors: [
                "textarea[aria-label*='Ask']",
                "textarea[placeholder*='Ask']",
                "[contenteditable='true'][role='textbox']",
                "textarea",
            ],
            sendButtonSelectors: [
                "button[aria-label='Submit']",
                "button[type='submit']",
                "button[aria-label*='Send']",
            ]
        ),
        .perplexity: genericAdapter(
            providerID: .perplexity,
            inputSelectors: [
                "textarea[placeholder*='Ask']",
                "textarea[placeholder*='Follow-up']",
                "textarea",
                "[contenteditable='true']",
            ],
            sendButtonSelectors: [
                "button[aria-label*='Submit']",
                "button[aria-label*='Send']",
                "button[type='submit']",
            ]
        ),
        .deepSeek: genericAdapter(
            providerID: .deepSeek,
            inputSelectors: [
                "textarea[placeholder*='Ask']",
                "textarea[placeholder*='问']",
                "textarea",
                "[contenteditable='true']",
            ],
            sendButtonSelectors: [
                "button[aria-label*='Submit']",
                "button[aria-label*='Send']",
                "button[type='submit']",
                "button[aria-label*='发送']",
            ]
        ),
    ]

    static func adapter(for providerID: ProviderID) -> (any ProviderAutomationAdapter)? {
        adapters[providerID]
    }

    private static func genericAdapter(
        providerID: ProviderID,
        inputSelectors: [String],
        sendButtonSelectors: [String]
    ) -> any ProviderAutomationAdapter {
        SelectorBasedProviderAdapter(
            providerID: providerID,
            configuration: ProviderDOMConfiguration(
                inputSelectors: inputSelectors,
                sendButtonSelectors: sendButtonSelectors,
                responseSelectors: [
                    "[data-message-author-role='assistant']",
                    "[data-testid*='assistant']",
                    ".prose",
                    ".markdown",
                ],
                streamingSelectors: [
                    "button[aria-label*='Stop']",
                    "button[data-testid*='stop']",
                    "[data-is-streaming='true']",
                ],
                loginSelectors: ["a[href*='login']", "button[data-testid*='login']"],
                rateLimitPhrases: ["rate limit", "usage limit", "too many requests"]
            )
        )
    }
}

private enum ProviderJavaScript {
    static func makeSubmitScript(
        message: String,
        inputSelectors: [String],
        sendButtonSelectors: [String],
        responseSelectors: [String]
    ) -> String {
        let messageLiteral = jsonLiteral(message)
        let inputSelectorsLiteral = jsonLiteral(inputSelectors)
        let sendButtonSelectorsLiteral = jsonLiteral(sendButtonSelectors)
        let responseSelectorsLiteral = jsonLiteral(responseSelectors)

        return """
        (async function() {
          const message = \(messageLiteral);
          const inputSelectors = \(inputSelectorsLiteral);
          const sendSelectors = \(sendButtonSelectorsLiteral);
          const responseSelectors = \(responseSelectorsLiteral);
          const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
          const visible = (node) => !!node && node.getClientRects().length > 0;

          const findFirstVisible = (selectors) => {
            for (const selector of selectors) {
              try {
                const node = Array.from(document.querySelectorAll(selector)).find(visible);
                if (node) return node;
              } catch (error) {}
            }
            return null;
          };

          const findSendButton = () => {
            for (const selector of sendSelectors) {
              try {
                for (const button of document.querySelectorAll(selector)) {
                  const disabled = button.disabled
                    || button.getAttribute("aria-disabled") === "true"
                    || button.classList.contains("disabled");
                  if (!disabled && visible(button)) return button;
                }
              } catch (error) {}
            }
            return null;
          };

          const setPromptValue = (input, value) => {
            const isTextInput = input.tagName === "TEXTAREA" || input.tagName === "INPUT";
            if (isTextInput) {
              const prototype = input.tagName === "TEXTAREA"
                ? window.HTMLTextAreaElement.prototype
                : window.HTMLInputElement.prototype;
              const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
              if (setter) setter.call(input, value); else input.value = value;
              input.dispatchEvent(new Event("input", { bubbles: true }));
              input.dispatchEvent(new Event("change", { bubbles: true }));
              return;
            }

            input.focus();
            if (input.isContentEditable) {
              try {
                document.execCommand("selectAll", false);
                document.execCommand("insertText", false, value);
              } catch (error) {}
              if (!input.textContent || input.textContent.trim() !== String(value).trim()) {
                input.textContent = value;
              }
              input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
              input.dispatchEvent(new Event("change", { bubbles: true }));
              return;
            }
            input.textContent = value;
          };

          const input = findFirstVisible(inputSelectors);
          if (!input) return { ok: false, error: "input-not-found" };

          const submissionToken = `llm-council-${Date.now()}-${Math.random().toString(16).slice(2)}`;
          try {
            for (const node of document.querySelectorAll(responseSelectors.join(","))) {
              node.dataset.llmCouncilBaseline = submissionToken;
            }
          } catch (error) {
            for (const selector of responseSelectors) {
              try {
                for (const node of document.querySelectorAll(selector)) {
                  node.dataset.llmCouncilBaseline = submissionToken;
                }
              } catch (selectorError) {}
            }
          }

          input.click();
          input.focus();
          setPromptValue(input, message);

          for (let attempt = 0; attempt < 30; attempt += 1) {
            const button = findSendButton();
            if (button) {
              button.click();
              return { ok: true, method: "button", submissionToken };
            }
            await sleep(60);
          }

          const form = input.closest("form");
          if (form && typeof form.requestSubmit === "function") {
            form.requestSubmit();
            return { ok: true, method: "form", submissionToken };
          }

          input.dispatchEvent(new KeyboardEvent("keydown", {
            key: "Enter", code: "Enter", which: 13, keyCode: 13,
            bubbles: true, cancelable: true
          }));
          input.dispatchEvent(new KeyboardEvent("keyup", {
            key: "Enter", code: "Enter", which: 13, keyCode: 13,
            bubbles: true, cancelable: true
          }));
          await sleep(100);
          return { ok: false, error: "send-not-triggered", submissionToken };
        })();
        """
    }

    static func makeCompletionProbeScript(
        responseSelectors: [String],
        streamingSelectors: [String],
        rateLimitPhrases: [String]
    ) -> String {
        """
        (function() {
          const responseSelectors = \(jsonLiteral(responseSelectors));
          const streamingSelectors = \(jsonLiteral(streamingSelectors));
          const rateLimitPhrases = \(jsonLiteral(rateLimitPhrases));
          const visible = (node) => !!node && node.getClientRects().length > 0;
          const hashText = (value) => {
            let hash = 2166136261;
            for (let index = 0; index < value.length; index += 1) {
              hash ^= value.charCodeAt(index);
              hash = Math.imul(hash, 16777619);
            }
            return (hash >>> 0).toString(16);
          };

          let nodes = [];
          try {
            nodes = Array.from(document.querySelectorAll(responseSelectors.join(",")));
          } catch (error) {
            const seen = new Set();
            for (const selector of responseSelectors) {
              try {
                for (const node of document.querySelectorAll(selector)) {
                  if (!seen.has(node)) {
                    seen.add(node);
                    nodes.push(node);
                  }
                }
              } catch (selectorError) {}
            }
            nodes.sort((left, right) => {
              if (left === right) return 0;
              return left.compareDocumentPosition(right) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
            });
          }

          const responses = nodes.map((node, index) => {
            const text = (node.innerText || node.textContent || "").trim();
            const stableID = node.getAttribute("data-message-id")
              || node.getAttribute("data-testid")
              || node.getAttribute("data-id")
              || node.id
              || `${node.tagName.toLowerCase()}:${index}`;
            return {
              node,
              text,
              baselineToken: node.dataset.llmCouncilBaseline || "",
              fingerprint: `${stableID}:${hashText(text)}`
            };
          });

          const nonEmptyResponses = responses.filter((response) => response.text.length > 0);
          const latest = nonEmptyResponses.length
            ? nonEmptyResponses[nonEmptyResponses.length - 1]
            : (responses.length ? responses[responses.length - 1] : null);
          const text = latest ? latest.text : "";
          let isStreaming = false;
          for (const selector of streamingSelectors) {
            try {
              if (Array.from(document.querySelectorAll(selector)).some(visible)) {
                isStreaming = true;
                break;
              }
            } catch (error) {}
          }
          if (latest) {
            isStreaming = isStreaming
              || latest.node.getAttribute("data-is-streaming") === "true"
              || latest.node.getAttribute("aria-busy") === "true";
          }

          const bodyText = (document.body?.innerText || "").toLowerCase();
          const matchedLimit = rateLimitPhrases.find((phrase) => bodyText.includes(phrase.toLowerCase())) || null;
          return {
            ok: true,
            responseCount: responses.length,
            responseFingerprints: responses.map((response) => response.fingerprint),
            latestFingerprint: latest ? latest.fingerprint : "",
            latestBaselineToken: latest ? latest.baselineToken : "",
            text,
            isStreaming,
            rateLimited: !!matchedLimit,
            rateLimitMessage: matchedLimit || ""
          };
        })();
        """
    }

    static func makeAuthenticationProbeScript(
        inputSelectors: [String],
        loginSelectors: [String]
    ) -> String {
        """
        (function() {
          const inputSelectors = \(jsonLiteral(inputSelectors));
          const loginSelectors = \(jsonLiteral(loginSelectors));
          const visible = (node) => !!node && node.getClientRects().length > 0;
          const hasVisible = (selectors) => selectors.some((selector) => {
            try { return Array.from(document.querySelectorAll(selector)).some(visible); }
            catch (error) { return false; }
          });
          const inputFound = hasVisible(inputSelectors);
          const loginFound = hasVisible(loginSelectors);
          return { authenticated: inputFound, inputFound, loginFound, readyState: document.readyState };
        })();
        """
    }

    static func makeRecoveryScript() -> String {
        """
        (function() {
          const selectors = [
            "button[aria-label*='Retry']",
            "button[aria-label*='Try again']",
            "button[data-testid*='retry']"
          ];
          for (const selector of selectors) {
            try {
              const button = Array.from(document.querySelectorAll(selector))
                .find((node) => node.getClientRects().length > 0 && !node.disabled);
              if (button) {
                button.click();
                return { ok: true, method: "button" };
              }
            } catch (error) {}
          }
          return { ok: true, method: "reload-required" };
        })();
        """
    }

    private static func jsonLiteral<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded
    }
}
