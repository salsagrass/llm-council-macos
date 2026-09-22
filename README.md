# llm-council-macos

> Product name: **LLM Council**

LLM Council is a local-first macOS app for side-by-side LLM web UI workflows (ChatGPT, Claude, Gemini, Grok, Perplexity, DeepSeek) with shared prompt dispatch, layout presets, and session persistence.

![](docs/llm-council.png)

## Why

Comparing responses across multiple model providers is slow when every prompt has to be copied manually between browser tabs. LLM Council keeps each provider in its own pane and lets you send one prompt to all visible providers from a single workspace.

## Features

- Multi-pane macOS workspace for provider web UIs
- Shared composer with send-to-visible/send-to-included flows
- Compare, Council, Thorough Council, and Rigorous Council modes
- Independent answers, blind peer review, revised positions, and ChatGPT Chairman synthesis
- Optional Claude/Gemini ratify-or-dissent round
- Fresh provider conversations by default for council runs
- Locally persisted council transcripts with intermediate responses, retries, and structured event logs
- Focus mode and direct/manual provider use
- Layout presets, pane paging, and zoom controls
- Prompt history, presets, and saved sessions
- Local-first persistence using `UserDefaults`
- Per-provider isolated web data stores

## Supported Providers

- ChatGPT
- Claude
- Gemini
- Grok
- Perplexity
- DeepSeek

Provider websites change over time. Automation adapters may need updates when provider DOM structures change.

Council mode currently uses ChatGPT, Claude, and Gemini. ChatGPT is always the
Chairman and cannot be removed from a council run. Compare mode retains all six
providers.

## Privacy and Data Model

- Local-first: workspace state, history, presets, and saved sessions are stored locally on your machine.
- No built-in cloud sync.
- No provider API keys are required by this app.
- You must use your own provider accounts through each provider's web interface.
- Council transcripts are stored as JSON in the app's Application Support directory.

## Build From Source (macOS)

See [BUILDING.md](BUILDING.md) for complete setup and troubleshooting.

Quick path:

```bash
./bin/bootstrap
./bin/build-macos
./bin/test-unit
./bin/smoke
```

## Verification Commands

- `./bin/build-macos`
- `./bin/test-unit`
- `./bin/test-ui`
- `./bin/smoke`
- `./bin/lint`
- `./bin/format`
- `./bin/deadcode`

## Limitations

- This app automates third-party websites; UI changes can break automation.
- Only activated/mounted provider panes can receive automated sends.
- Provider login/session state is managed by each provider website in its pane.
- Council completion detection relies on provider-specific WebView adapters and may need maintenance when a provider changes its site.

## Council Architecture

See [docs/council-protocol.md](docs/council-protocol.md) for the repository
audit, extension points, deliberation state machine, and WebView adapter
boundary.

## Project Status

Early open-source release. APIs and project structure can change quickly while the app hardens.

## Security

Please read [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening issues or pull requests.

## Contributors

See [CONTRIBUTORS.md](CONTRIBUTORS.md).

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

LLM Council is an independent project and is not affiliated with or endorsed by OpenAI, Anthropic, Google, xAI, Perplexity, or DeepSeek.
