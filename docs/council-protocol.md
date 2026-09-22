# Multi-agent council extension

## Repository audit

The app is a single-target macOS SwiftUI application. `WorkspaceStore` owns the
persisted compare-workspace state, `WorkspaceView` owns the mounted `WKWebView`
instances through `WebViewHub`, and `ProviderAdapters.swift` contains the
provider DOM selectors and JavaScript used by shared prompt dispatch.

Provider authentication is not brokered by the app. Each provider is loaded in
its own persistent `WKWebsiteDataStore`, so existing web sessions remain
isolated and survive application restarts. The current shared-send path is
send-only: it does not detect streaming completion or extract responses.

## Minimal extension points

1. Keep provider DOM knowledge in `ProviderAdapters.swift`.
2. Make `WebViewHub` implement a stable `CouncilProviderClient` boundary:
   submit, wait for completion, extract the latest response, start a fresh
   conversation, check authentication, and recover from failure.
3. Put deliberation order, anonymization, prompts, retries, stop behavior, and
   persistence in provider-independent council types.
4. Keep Compare mode and direct/manual provider panes intact. Council modes use
   the same mounted WebViews and persistent provider data stores.
5. Render council transcripts in a separate workspace surface while the live
   provider panes remain mounted behind it.

## Implementation sequence

1. Add codable council models, stage planning, anonymization, and prompt
   builders.
2. Add local run persistence and a coordinator that advances only after every
   provider in a stage has either completed or explicitly failed/timed out.
3. Extend provider adapters with completion, authentication, and extraction
   probes; add async WebView operations at the hub boundary.
4. Add Compare, Council, Thorough Council, and Rigorous Council UI modes,
   participant selection, fresh-chat isolation, stop controls, retry controls,
   response copying, and archived-run inspection.
5. Add unit tests for chairman enforcement, anonymization, stage transitions,
   retry replacement, persistence, and fresh-chat preparation.

The chairman is a computed invariant (`ChatGPT`) rather than a configurable
field. No provider API or coding-agent CLI participates in council inference.
