# Goal Tasks

Status legend: `[ ]` pending, `[~]` in progress, `[x]` complete.

## Task 1: SwiftData Startup Recovery

Status: [x]

Replace fatal launch failure on SwiftData container creation with a recoverable app state. Add diagnostics/retry/fresh-store affordances where safe, and tests for recovery-state decisions.

Work performed:

- Replaced launch-time `fatalError` SwiftData container creation with `StartupModelContainerState` and a recoverable startup flow.
- Added `StartupRecoveryService` with persistent-container open reporting, redacted diagnostics, temporary in-memory container creation, and safe backup/reset of SwiftData store files.
- Added `StartupRecoveryView` for retry, copy diagnostics, reveal store folder, temporary session, and backup/rebuild actions.
- Updated app and Settings scenes to render recovery UI when persistence is unavailable, reject native browser handoffs with `persistenceUnavailable`, and guard startup configuration so incomplete-task restoration does not repeat on SwiftUI view rebuilds.
- Added SwiftData persistence helpers for default store URL/configuration and temporary containers.
- Added English and Simplified Chinese startup recovery localization.
- Added tests covering non-crashing container failure reporting, temporary recovery containers, store-file-only backups, missing-store refusal, and unsafe directory/empty-path refusal.
- Restored the accidentally renamed `Sources 2` workspace directory back to `Sources` so SwiftPM can resolve package targets.

Verification evidence:

- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- `swift test --filter startupRecovery` passed: 4 tests.
- `swift test --filter PersistenceArchive` passed: 13 tests.
- `swift test` passed: 296 tests in 22 suites.

Remaining risk:

- Recovery UI was verified by build/tests and static review, not an interactive manual app launch. Manual QA should still exercise a deliberately corrupted SwiftData store in a packaged app before release.
- Backup/rebuild intentionally moves only detected SwiftData store files and sidecars; downloaded payload files are not touched.

Next step:

- Task 2: Authenticated Download Recovery UX and POST Policy.

## Task 2: Authenticated Download Recovery UX and POST Policy

Status: [ ]

Make runtime-only browser credentials visible as a task/session constraint, prevent misleading post-restart retries, and add a safe POST/body policy that falls back to the browser unless replay is explicitly supported.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Task 3: Browser End-to-End Validation Harness.

## Task 3: Browser End-to-End Validation Harness

Status: [ ]

Add a repeatable browser handoff validation harness or documented local test runner covering extension-to-native-host-to-app accepted, rejected, cancelled, timeout, version mismatch, and fallback flows.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Large Check 1: Startup, Auth, and Browser Reliability.

## Large Check 1: Startup, Auth, and Browser Reliability

Status: [ ]

Review Tasks 1-3 for requirement drift, data safety, browser fallback behavior, tests, build status, docs, and rollback risk. Fix discovered issues before marking complete.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Task 4: Proxy and Network Policy.

## Task 4: Proxy and Network Policy

Status: [ ]

Add HTTP proxy settings and request plumbing where feasible, with redacted diagnostics and a documented path for BT/SOCKS5 proxy support.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Task 5: Browser Permission and Takeover Controls.

## Task 5: Browser Permission and Takeover Controls

Status: [ ]

Surface extension permission rationale and takeover rules in the app/docs. Align app-side settings with extension options for host, extension, size, and bypass behavior where feasible.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Task 6: Failure Diagnosis and Recovery Actions.

## Task 6: Failure Diagnosis and Recovery Actions

Status: [ ]

Improve user-facing recovery for common failures: auth/session expiry, HTTP status failures, checksum mismatch, permission/disk issues, stale metadata, and partial data.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Large Check 2: Network Policy and Recovery UX.

## Large Check 2: Network Policy and Recovery UX

Status: [ ]

Review Tasks 4-6 for security, diagnostics redaction, settings persistence, localization, test coverage, and regression risk. Fix discovered issues before marking complete.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Task 7: Visual Download Rules and Scheduling UX.

## Task 7: Visual Download Rules and Scheduling UX

Status: [ ]

Improve download-rule editing/validation and add scheduled or conditional queue controls where feasible without overreaching platform permissions.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Task 8: BitTorrent Real-Network Readiness.

## Task 8: BitTorrent Real-Network Readiness

Status: [ ]

Add a deterministic acceptance matrix and optional local/manual validation harness for real-network BT behavior: public torrent, DHT-only, weak network, restart/resume, relocation, private torrent restrictions, and seeding policy.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Task 9: Protocol and Packaging Tracks.

## Task 9: Protocol and Packaging Tracks

Status: [ ]

Document or scaffold realistic next paths for Safari production App Extension packaging, Firefox Native Messaging, HLS/DASH, Metalink, multi-source, FTP/SFTP, crash/local observability, and release dry-run validation.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Large Check 3: Scheduling, Torrent, Protocols, and Release Tracks.

## Large Check 3: Scheduling, Torrent, Protocols, and Release Tracks

Status: [ ]

Review Tasks 7-9 for scope fidelity, docs/source consistency, test/build status, external credential limits, and user-facing completeness. Fix discovered issues before marking complete.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Task 10: Release Dry-Run Validation.

## Task 10: Release Dry-Run Validation

Status: [ ]

Run or improve local release dry-run validation for non-secret checks, verify clear failures for missing credentials, and document exact release readiness evidence.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Final Review.

## Final Review

Status: [ ]

Run a full completion audit against `goal-2/plan.md`, the current codebase, tests, docs, scripts, and runtime-verifiable behavior. Fix and retest until no known required work remains, then mark the built-in goal complete.

Work performed:

- Pending.

Verification evidence:

- Pending.

Remaining risk:

- Pending.

Next step:

- Complete active goal if and only if evidence proves all requirements.
