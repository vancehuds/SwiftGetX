# Goal Tasks

Status legend: `[ ]` pending, `[~]` in progress, `[x]` complete.

## Task 1: Browser Takeover App Ack

Status: [x]

Implement a real acknowledgment path between `SwiftGetXNativeHost` and the app so browser takeover only reports success when the app has accepted, queued, or explicitly rejected the task. Update native-host response fields to include accepted/queued/confirmation/rejection details and add tests for success, user/app rejection, and timeout fallback.

Work performed:

- Added a one-shot loopback acknowledgement channel in `SwiftGetXCore` with `NativeHandoffAck`, `NativeHandoffAckDecision`, `NativeHandoffAckClient`, and `NativeHandoffAckServer`.
- Extended `DeepLinkBuilder.downloadURL` and `DeepLinkParser.downloadDraft` to carry `ackRequestID`, `ackToken`, and `ackPort`.
- Updated `SwiftGetXNativeHost` download handling to start the ack server, open the deep link with ack metadata, wait for an App decision, and return `ok`, `accepted`, `queued`, `requiresUserConfirmation`, `rejectedReason`, and `requestID`.
- Updated App handling so direct browser handoffs acknowledge after task creation, and confirmation-sheet handoffs acknowledge accepted on Add or rejected on Cancel/dismiss.
- Added `NativeHandoffDecisionFactory` so zero created tasks are rejected instead of reported as accepted.

Verification evidence:

- `swift test --filter NativeMessageHost` passed with 11 tests, including accepted callback, user cancellation rejection, timeout fallback, response fields, deep-link ack parsing, and empty-task rejection coverage.
- `swift test` passed with 81 tests across 12 suites.

Remaining risk:

- The ack timeout is currently 60 seconds, which protects Chrome from indefinite waiting but may still be short for a user who leaves the confirmation sheet open. Later takeover-policy work should make timeout/fallback behavior user-configurable or extension-visible.
- This task only establishes the ack loop; richer browser context and deeper deep-link trust hardening remain in later tasks.

Next step:

- Task 2: Browser Download Context.

## Task 2: Browser Download Context

Status: [ ]

Extend browser/native message models and extension code to carry the minimum useful authenticated context: referrer, user agent, selected headers, method, optional body metadata, final/suggested filename metadata, and redacted source information. Ensure sensitive headers/cookies are not logged in plain text.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 3: Browser Diagnostics and Multi-Browser State

Status: [ ]

Replace static browser readiness UI with live diagnostics for native host, extension IDs, manifest paths, supported Chromium variants, and app/native-host compatibility. Extend registrar/discovery for Edge, Brave, Vivaldi, Arc, Chromium, and Chrome Canary where local path conventions are known.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 1: Browser Takeover Foundation

Status: [ ]

Review requirement drift, native-host failure modes, extension rollback behavior, deep-link security, build/test status, and docs for Tasks 1-3. Fix discovered issues before marking complete.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 4: Deep-Link Safety and Payload Limits

Status: [ ]

Add safety limits and validation for public `swiftgetx://download` links: task count, URL length, dangerous schemes/characters, multi-link confirmation defaults, and trusted/native-host handoff distinction. Add tests for malicious or oversized payloads.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 5: Extension Scanning and Takeover Rules

Status: [ ]

Improve extension scanning and takeover control: partial candidate selection, site/file-type/size rules, visible popup errors, and fallback when payloads exceed deep-link length. Prefer native messaging for large payloads or temporary JSON handoff where appropriate.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 6: HTTP Metadata and Content-Disposition

Status: [ ]

Parse `Content-Disposition` (`filename*` and `filename`), MIME type, final URL, redirect/source metadata, and server support details. Use this metadata in task creation and tests.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 2: Browser and HTTP Metadata

Status: [ ]

Review Tasks 4-6 for security, parser correctness, localization, tests, and compatibility with existing download flows. Run targeted tests and fix issues.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 7: HTTP New-Task Preview

Status: [ ]

Add HTTP HEAD/Range metadata preview before creating tasks, including filename, size, resumability, final URL, content type, duplicate-file strategy, and failure fallback.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 8: Per-Task Download Options and Persistent Speed Settings

Status: [ ]

Add per-task overrides for segment count, retry limit, speed limit, save path, filename, and headers. Ensure toolbar speed-limit changes persist through `AppSettings` or are explicitly modeled as temporary limits.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 9: Queue Scheduling and Restart Policy

Status: [ ]

Implement queue ordering/reordering, priority, automatic queue fill when concurrency increases, failed-task backoff/requeue behavior, restart policy for incomplete tasks, and remove or replace fixed 500-task assumptions where they affect scheduling/statistics.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 3: HTTP Task Control

Status: [ ]

Review Tasks 7-9 for data migration, settings consistency, user-facing behavior, scheduler edge cases, and tests. Run `swift test` if Swift code changed.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 10: Failure Recovery, Cancellation, and File Preflight

Status: [ ]

Add a distinct cancelled state, retry/copy-error/reprobe/rename-and-continue actions, HTTP status-specific user messages, disk-space and permission preflight, and clear retain/delete/open partial-file operations.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 11: SwiftGetXTorrentCore Target and Metadata Parsers

Status: [ ]

Create `SwiftGetXTorrentCore` and implement/test bencode, canonical info bytes, v1 info hash, single/multi-file metainfo, announce-list/private flag parsing, and magnet parsing for hex/base32 `btih`, `dn`, `tr`, and `xl`.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 12: Torrent Path Layout and Resume Schema

Status: [ ]

Implement `TorrentContentLayout` with explicit save directory, content root, file paths, offsets, lengths, priorities, path traversal protection, duplicate path detection, control-character/length checks, and a pure Swift resume-state schema.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 4: Torrent Metadata Foundation

Status: [ ]

Review Tasks 10-12 for data-model migrations, path safety, parser limits, tests, and docs. Confirm no release dependency on libtorrent was added.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 13: BT Save Path Semantics and Deletion Boundaries

Status: [ ]

Split or clarify BT save directory, output name, final file path/content root path, UI display paths, and local deletion confirmation so single-file and multi-file torrents cannot delete the wrong directory or miss actual content.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 14: Swift Torrent Adapter Skeleton and Engine Status

Status: [ ]

Add `SwiftTorrentEngineAdapter` behind the existing `TorrentEngineAdapter` boundary, expose engine type/status in UI/settings, keep libtorrent optional, and wire metadata/layout preview without requiring libtorrent.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 15: Tracker Client and Mock Tracker Tests

Status: [ ]

Implement HTTP and UDP tracker announce basics, compact/non-compact peer parsing, tier scheduling, retry/timeout state, scrape placeholders, diagnostics snapshots, and deterministic local mock tests.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 5: Swift Torrent Adapter and Tracker

Status: [ ]

Review Tasks 13-15 for adapter isolation, UI compatibility, network input validation, test determinism, and build status.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 16: Peer Wire MVP and Torrent Storage

Status: [ ]

Implement minimal TCP peer-wire handshake/messages, request pipeline, block limits, piece SHA-1 validation, single/multi-file storage writes across boundaries, pause/resume/delete partial data, and mock peer tests.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 17: Real Swarm MVP and Runtime Snapshots

Status: [ ]

Implement multi-peer connection pooling, rarest-first and endgame behavior, peer scoring, global/per-task speed limits, tracker completed/stopped events, and `DownloadSnapshot` mapping for files, peers, trackers, health, speed, ETA, and runtime options.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 18: Magnet Metadata

Status: [ ]

Implement BEP 10 extension handshake and BEP 9 `ut_metadata` exchange, metadata assembly and info-hash verification, fetching-metadata UI state, timeout actions, and mock extended-peer tests.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 6: Peer Wire and Magnet MVP

Status: [ ]

Review Tasks 16-18 for protocol safety, storage consistency, piece verification, resume behavior, UI state transitions, and deterministic tests.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 19: DHT, PEX, and LSD

Status: [ ]

Implement or clearly gate DHT KRPC/routing/bootstrap/get_peers/announce_peer, PEX, LSD, persisted DHT nodes, settings toggles, source statistics, and local mock tests for non-network behavior.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 20: Seeding State and Policies

Status: [ ]

Add `seeding` status, upload speed, share ratio, seeding time, per-task/global seeding policies, completion versus seeding-stop notifications, and stop-at-ratio/time/never-stop behavior.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 21: Torrent File Priority and Advanced UX

Status: [ ]

Support live file/folder priority, skip/low/normal/high, folder-level selection, extension filters, sequential download mode, recheck existing files, move/relocate downloads, and batch tracker operations.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 7: Advanced Torrent UX

Status: [ ]

Review Tasks 19-21 for correctness, feature gating, UI consistency, migration needs, and optional libtorrent parity.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 22: Batch Task Management and Categories

Status: [ ]

Add multi-select task UI and batch start/pause/delete/recheck/move/limit actions, cleanup completed/failed, categories/tags/smart filters, archive behavior, and clear local-file deletion confirmation.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 23: Drag-and-Drop and System Integration

Status: [ ]

Add drag-and-drop URL/text/torrent handling, Finder `.torrent` open-with plumbing where possible, Services/Share Extension plan or implementation, Dock progress/badge, and menu-bar progress refinements.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 24: Inspector, Logs, Accessibility, and Localization

Status: [ ]

Add HTTP segment details, average/peak speed, start/finish/duration metadata, log clear/export/copy actions, direct error-card actions, VoiceOver labels, keyboard shortcuts, reduced-transparency handling, and hard-coded string cleanup.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 8: Main UI and Accessibility

Status: [ ]

Review Tasks 22-24 for UX regressions, layout, localization, keyboard/VoiceOver coverage, data performance, and tests/build status.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 25: Download Rules and System Behavior Settings

Status: [ ]

Add rules for domain/extension/size save directories, thread counts, auto-start, browser takeover allow/deny lists, site headers/auth config, filename templates, login item, menu-bar background behavior, sleep prevention, exit prompts, and completion actions where local APIs permit.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 26: Persistence, Sensitive Data, and Large-Scale Performance

Status: [ ]

Add schema migration strategy for new fields, robust JSON recovery/cleanup, import/export, Keychain or runtime-only sensitive header storage, URL/log redaction, paged fetches/archiving, and menu-bar snapshot performance safeguards.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 27: Filesystem Safety and Protocol Expansion Boundaries

Status: [ ]

Add disk-space/permission checks, safe deletion boundary checks, HTTP preallocation/capacity detection where possible, torrent sandbox/path checks, and document/test protocol expansion boundaries for FTP/SFTP, Metalink, HLS/DASH, multi-source, and GitHub/GitLab assets.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 9: Settings, Persistence, and Filesystem Safety

Status: [ ]

Review Tasks 25-27 for settings consistency, security, data migration, privacy, and large-library behavior. Run broad tests.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 28: Sparkle, Signing, Notarization, and Release Gates

Status: [ ]

Replace or enforce Sparkle public-key configuration, add release workflow checks for required secrets, signing/notarization verification commands, manual update status feedback, release notes wiring, and local-build-safe fallback behavior.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 29: Extension Distribution, Version Compatibility, and Licenses

Status: [ ]

Add extension/app/native-host version compatibility checks, Chrome extension release packaging path, installation guidance, fixed-ID strategy documentation, dependency/license acknowledgements, and optional libtorrent dependency cleanup guidance.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Task 30: Test, Diagnostics, and Support Tooling

Status: [ ]

Add browser E2E-friendly fixtures, torrent mock tracker/peer/DHT fixtures, network/file exception tests, UI/accessibility test coverage where feasible, diagnostic bundle export, redacted debug logs, crash-log guidance, extension popup native-message error details, and copy-diagnostics action.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Large Check 10: Release and Quality

Status: [ ]

Review Tasks 28-30 for release trust, diagnostics privacy, CI feasibility, docs, and complete test status.

Work performed:

Verification evidence:

Remaining risk:

Next step:

## Final Review: Full Plan Completion Audit

Status: [ ]

Perform a requirement-by-requirement audit against `Docs/FunctionalImprovementOpportunities.md`. Verify source, tests, docs, release scripts, and runtime behavior where possible. Fix all unresolved issues, run final tests, record evidence, and only then mark the built-in goal complete.

Work performed:

Verification evidence:

Remaining risk:

Next step:
