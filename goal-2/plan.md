# Goal Plan

## Objective

Implement the stability and functionality recommendations from the latest SwiftGetX review, preserving the original scope of "implement these suggestions" while making incremental, verified progress each session.

## Requirements

1. Browser end-to-end reliability
   - Add a repeatable validation path for Chrome extension plus Native Host plus App handoff.
   - Cover accepted takeover, user cancellation, App rejection, Native Host version mismatch, timeout, extension fallback to browser download, and visible popup errors.
   - Mirror or document Safari behavior where full signed App Extension packaging cannot be completed in SwiftPM alone.

2. SwiftData startup recovery
   - Replace launch-time `fatalError` on `ModelContainer` creation failure with a recoverable app state.
   - Provide user-visible recovery options: retry, create diagnostics, backup/replace damaged store when safe, and continue with a fresh store where possible.
   - Add tests for recovery-state behavior without corrupting user data.

3. Authenticated download recovery and POST policy
   - Make runtime-only sensitive headers/cookies understandable to users after restart/resume.
   - Prevent misleading retries when credentials were intentionally not persisted.
   - Add a clear policy for POST/body downloads: safe browser fallback by default unless replay is explicitly implemented and audited.

4. BitTorrent real-network readiness
   - Keep deterministic mock coverage while adding an acceptance checklist and optional local/manual validation harness for public torrents, DHT-only discovery, weak networks, restart/resume, relocation, private torrent restrictions, and seeding policies.
   - Do not depend on external network in required CI tests.

5. Proxy and network policy
   - Add HTTP proxy configuration where feasible and design hooks for BT/SOCKS5 proxy support.
   - Ensure proxy settings are persisted, redacted in diagnostics, and covered by tests.

6. Browser permission and takeover controls
   - Explain extension permissions in app/docs.
   - Add app-side controls or clear routing for takeover policy: site, extension, size, and bypass rules.
   - Keep sensitive request context bounded and redacted.

7. Download rules and scheduling UX
   - Improve the existing rule system with a more visual editing/validation path.
   - Add scheduled/conditional download policies where feasible: delayed start, queue policy, power/network-related constraints if locally implementable.

8. Failure diagnosis and recovery actions
   - Add user-facing diagnosis actions for common HTTP failures, checksum failures, missing files, permission issues, and auth/session expiry.
   - Include "retry from browser/session", copy diagnostics, refresh metadata, and partial-data actions where appropriate.

9. Future protocol and packaging tracks
   - Document and scaffold realistic next paths for Safari production extension packaging, Firefox Native Messaging, HLS/DASH, Metalink, multi-source, FTP/SFTP, and crash/local observability.
   - Avoid claiming external-credential tasks are complete unless current evidence proves them.

10. Release dry-run validation
   - Verify local non-secret release gates and document required secrets.
   - Add checks that fail clearly when Developer ID, notary, Sparkle private key, or Chrome fixed ID inputs are absent.

## Default Assumptions

- Goal mode is active; do not ask clarifying questions.
- External accounts, Apple Developer ID/notary credentials, Chrome Web Store credentials, and real Sparkle private keys are not assumed available.
- Required automated tests should avoid external network dependencies.
- Keep changes scoped, compatible with the current SwiftPM app, and consistent with existing SwiftData/SwiftUI patterns.
- Preserve prior goal files and user changes. Use `goal-2` for this current objective.

## Execution Plan

Work sequentially through `goal-2/tasks.md`. Each task must produce code/docs/tests or validation evidence that directly moves the objective toward completion. After every three implementation tasks, run a large check/debug cycle. Do not mark the built-in goal complete until every requirement above is implemented or strictly proven blocked under the goal-mode rules.

## Verification Plan

- Run focused Swift tests for each changed subsystem.
- Run `swift test` after substantial Swift changes.
- Run `node --check` and JSON parsing for extension JavaScript/locales when touched.
- Use static inspection and tests for browser-extension fallback behavior unless a full local browser automation harness is implemented.
- Use release validation scripts for packaging/release work; document any external-secret limits as unresolved until proven.
- Record evidence under the completed task in `goal-2/tasks.md`.

## Rollback Plan

- Keep each task small enough to revert independently.
- Avoid destructive data operations unless explicitly implemented behind user confirmation and backed by tests.
- Gate risky new behavior behind settings or fallback paths.
- Preserve optional libtorrent and existing SwiftTorrent behavior while adding validation or UX around it.

## Completion Criteria

- All tasks and large check/debug cycles in `goal-2/tasks.md` are complete.
- Current source, tests, docs, and scripts prove every requirement above is satisfied or the strict blocked audit has been met.
- `swift test` passes, plus targeted JS/release checks relevant to touched files.
- The active built-in goal is marked complete only after a requirement-by-requirement completion audit proves no required work remains.
