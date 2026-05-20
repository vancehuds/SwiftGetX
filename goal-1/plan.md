# Goal Plan

## Objective

Complete the functional improvement plan in `Docs/FunctionalImprovementOpportunities.md` for SwiftGetX. The plan spans browser takeover reliability, authenticated browser download context, HTTP download metadata and configuration, queue and batch management, a pure Swift BitTorrent path, task UI improvements, settings consistency, data/security hardening, release/update trust, and expanded testing/diagnostics.

## Scope

The source of truth is the current worktree plus `Docs/FunctionalImprovementOpportunities.md`. Success requires implementing or otherwise resolving the plan's concrete recommendations, then verifying each requirement against current code, tests, docs, and runtime behavior where applicable.

## Requirements Summary

- Browser integration:
  - Add a real App acknowledgment path for Chrome/native-host takeover so Chrome cancels native downloads only after SwiftGetX has accepted or queued the task.
  - Carry minimum useful browser context such as referrer, user agent, selected headers, method, optional body metadata, and safer source information.
  - Show real extension/native-host/browser diagnostics in the app instead of static readiness copy.
  - Support more Chromium variants and prepare Safari/Firefox paths where local constraints allow.
  - Improve scanning, takeover rules, failure reporting, deep-link safety, payload length handling, and trusted handoff boundaries.
- HTTP/HTTPS downloads:
  - Parse `Content-Disposition` and response metadata, expose metadata preview before task creation, and record final URL/MIME/source details.
  - Add checksum/integrity status and user actions for failed verification.
  - Support per-task options for segments, retry limit, speed limit, save path, filename, and headers.
  - Improve queue scheduling, task ordering, restart policy, large task sets, failure recovery, cancellation semantics, and disk/permission preflight.
  - Expand protocol strategy where feasible or explicitly document deferred protocols with tests around the existing boundaries.
- BitTorrent:
  - Establish `SwiftGetXTorrentCore` as the pure Swift core target and keep `TorrentEngineAdapter` as the adapter boundary.
  - Implement bencode, metainfo, magnet parsing, info hash, path-safe content layout, resume-state design, and tests.
  - Correct BT save path semantics and local deletion boundaries.
  - Add tracker, peer-wire, storage, piece verification, mock tracker/peer fixtures, magnet metadata, DHT/PEX/LSD, seeding state, file priority, and advanced BT UX progressively.
  - Keep libtorrent optional as a reference only until the Swift engine is proven, then remove or clearly downgrade release dependencies.
- Main UI and task management:
  - Add multi-select and batch operations, queue ordering and categories, drag-and-drop/system integrations, stronger new-task preview, inspector segment/log details, accessibility labels, keyboard paths, and localization cleanup.
- Settings and policy:
  - Ensure every speed-limit entry point persists through `AppSettings` or is explicitly temporary.
  - Add domain/extension/size rules, browser takeover allow/deny lists, filename templates, login/background/sleep/exit/download-completion behavior where supported.
- Persistence and security:
  - Plan schema migration for new fields, robust JSON recovery, import/export, sensitive header/token protection, URL/log redaction, large-list performance, and filesystem safety.
- Release/update/install:
  - Replace Sparkle placeholder key with a real configurable key path or enforce release-time failure while keeping local builds usable.
  - Add signing/notarization checks, native host/extension version compatibility checks, release dependency acknowledgements, and clearer optional libtorrent licensing.
- Testing and quality:
  - Add unit, integration, and UI-adjacent tests for browser failures, torrent parser/security, tracker/peer mocks, network/file failures, localization/accessibility where feasible.
  - Run `swift test` and targeted build/test commands after relevant tasks.
  - Record verification evidence in `goal-1/tasks.md`.

## Default Assumptions

- Do not ask clarifying questions in goal mode; choose conservative behavior consistent with the current codebase.
- Apple Developer ID credentials, notary credentials, Chrome Web Store publishing credentials, Sparkle signing private keys, and real external accounts are not assumed to be available in this workspace. Where external credentials are required, implement local validation, placeholders that fail release workflows clearly, and documentation. Do not mark credential-bound requirements complete unless current evidence proves they are configured.
- Avoid external network dependencies in tests. Prefer local mock HTTP servers, mock trackers, mock peers, fixtures, and deterministic parser tests.
- Keep libtorrent support optional while building the Swift engine. Do not remove existing optional libtorrent code until equivalent Swift behavior has verified coverage.
- Preserve existing user or generated work in the dirty worktree unless it directly conflicts with the task.

## Execution Plan

Work through `goal-1/tasks.md` sequentially. Each implementation task must be independently verifiable. After every three implementation tasks, run a large check/debug cycle covering requirement drift, bugs, type/build/test status, UI behavior when relevant, security, data consistency, rollback needs, and documentation sync.

## Verification Plan

- Static inspection: compare source and docs against each requirement before claiming completion.
- Builds/tests: run `swift test` after tasks that touch Swift code; run targeted tests first when faster. Run `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` only when native libtorrent paths are changed and the archive/prerequisites are present.
- Browser-extension checks: verify manifest/background/popup/native-host message schema changes with parser/unit tests where possible.
- Torrent checks: cover parser, path safety, tracker/peer mocks, piece hash failure, resume state, and adapter snapshots with deterministic tests.
- UI checks: run builds and inspect SwiftUI code paths; use local browser/UI verification only when a runnable UI flow is changed and tool support is available.
- Release checks: verify scripts/workflows fail clearly when required secrets or keys are absent, and pass local non-release builds.

## Rollback Plan

- Keep changes small and task-scoped.
- Use tests and diffs to isolate regressions.
- If a task introduces a high-risk behavior change, gate it behind settings or feature flags until verified.
- Do not delete existing libtorrent, browser, release, or user-data paths until replacement behavior is implemented and tested.

## Completion Criteria

- Every explicit requirement in `Docs/FunctionalImprovementOpportunities.md` is either implemented and verified, or explicitly marked as impossible/blocking due to unavailable external credentials after the strict blocked audit threshold.
- All tasks and large check/debug cycles in `goal-1/tasks.md` are complete.
- Final review confirms current code, docs, tests, release scripts, and runtime behavior align with the original plan.
- `swift test` passes, plus relevant optional commands where prerequisites exist.
- The active built-in goal is marked complete only after requirement-by-requirement evidence proves completion.
