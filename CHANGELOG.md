# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning where practical.

## [Unreleased]

### Added

- Initial open-source release hardening docs and governance files.
- Council, Thorough Council, and Rigorous Council deliberation modes using existing logged-in ChatGPT, Claude, and Gemini WebViews.
- Blind response anonymization, peer review, revised positions, permanent ChatGPT Chairman synthesis, and optional Claude/Gemini ratify-or-dissent.
- Fresh-chat isolation, streaming completion detection, response extraction, explicit timeout/rate-limit failures, individual retry, stop controls, local transcript persistence, and structured logs.

### Changed

- Repository sanitized for public distribution (generated artifacts and local-only files removed from tracking).
- Compare mode, manual provider panes, isolated persistent web data stores, and all existing provider support remain intact alongside council mode.

### Fixed

- The shared prompt composer now accepts click focus and keyboard input reliably; `Command-Return` submits while plain Return inserts a new line.
- Provider submissions now await asynchronous JavaScript results through WebKit's async bridge instead of failing when an unresolved Promise crosses into Swift.
- Fresh council runs now verify blank provider conversations, track response DOM identity and fingerprints, select responses in DOM order, and stop when a prerequisite round lacks usable results.
- ChatGPT submissions now wait for its composer state to stabilize, verify that the exact current-run prompt was submitted, and accept only a response that follows that prompt.
