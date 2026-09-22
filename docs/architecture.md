# Architecture

Keep this file short. It is the durable mental model for the repo.

## App shape
- Main app targets: `LLM Council` (macOS SwiftUI app), `LLM CouncilTests`, `LLM CouncilUITests`.
- Local Swift packages: None yet.
- Shared modules: App-internal feature files for workspace state, provider adapters, WebKit panes, and the provider-independent council coordinator.
- External services / SDKs: WebKit (`WKWebView`) for embedded provider websites; no direct provider API SDKs in v1.

## State & navigation
- State management approach: `WorkspaceStore` owns provider registry, pane states, composer text, shared prompt-dispatch state, history, presets, saved sessions, and focus mode. `CouncilCoordinator` owns persisted multi-round council runs. Window-scoped `WorkspaceChromeState` owns transient shell UI such as selected mode/provider, sidebar selection, inspector visibility, and which providers have been activated into live webviews.
- Navigation approach: Single-window workspace with a source-list sidebar (`Workspace`, `Providers`, `History`, `Presets`, `Saved Sessions`), a compare canvas in detail, and a trailing inspector for workspace controls plus selected-provider details. The bottom global composer is docked with `safeAreaInset`, and native macOS toolbar/menu commands drive send/focus/inspector actions.
- Dependency injection approach: App scene creates one workspace store and injects it into root views. WebKit panes receive adapter/config dependencies from the store.

## Data flow
- Networking layer: No custom networking in app code for provider chats. Providers load directly in embedded webviews after an app-owned idle state activates a pane into a live session. Council inference uses those same web sessions through `CouncilProviderClient`; no model API or coding-agent CLI is used.
- Persistence layer: Local-only persistence for workspace settings, prompt history, presets, and saved sessions via `UserDefaults` snapshot storage. Full council transcripts and structured event logs are atomically stored in Application Support as JSON. Theme selection is persisted locally via app storage. Provider auth sessions persist via provider-specific `WKWebsiteDataStore` identifiers. Saved session restores reload provider chat URLs in mounted panes and hydrate lazy panes on mount.
- Caching / offline rules: No cloud sync in v1. Last local workspace state restores on launch; provider session/cookie storage is isolated per provider.

## Project boundaries
- Code that belongs in app targets: SwiftUI app shell, sidebar/toolbar/inspector/composer UI, pane controls, provider adapter interfaces, and the WebKit bridge.
- Code that belongs in packages: None yet; move shared logic to package once feature area grows (for example adapter/testing utilities).
- Areas that should stay decoupled: Provider-specific DOM automation scripts from `CouncilCoordinator`, core workspace state, and the generic WebKit view wrapper. The coordinator depends only on submit, completion, extraction, new-conversation, authentication, and recovery operations.

## Current architectural constraints
- Constraint 1: DOM automation for third-party chat sites is brittle and must fail gracefully without blocking manual use.
- Constraint 2: The app is macOS single-window and local-first, with no account brokering or cloud sync.
- Constraint 3: Only activated/mounted provider panes can receive automated sends; the shell now owns idle/loading placeholders, but provider websites still take over once a session is active.
- Constraint 4: Tests that require macOS test runner services may fail in strict sandbox mode; run verification scripts with elevated permissions when needed.
