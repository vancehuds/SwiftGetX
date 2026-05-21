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

Status: [x]

Extend browser/native message models and extension code to carry the minimum useful authenticated context: referrer, user agent, selected headers, method, optional body metadata, final/suggested filename metadata, and redacted source information. Ensure sensitive headers/cookies are not logged in plain text.

Work performed:

- Added `BrowserDownloadContext`, `BrowserDownloadHeader`, and `BrowserDownloadBodyMetadata` in `SwiftGetXCore` to represent referrer, user agent, method, selected headers, body metadata, final/original URLs, suggested filename, source page, and handoff source.
- Extended `BrowserDownloadMessage` to carry structured context while preserving existing top-level fields for compatibility.
- Extended the native-host handoff server with a token-protected `/payload` endpoint, so the App can fetch full browser context over localhost instead of putting sensitive headers into the public `swiftgetx://` URL.
- Updated `SwiftGetXNativeHost` to build context from incoming native messages and provide it through the handoff payload.
- Updated App deep-link handling, `DownloadDraft`, `BrowserBridge`, `NewTaskSheet`, `DownloadCoordinator`, and `DownloadRequest` so browser context flows into created tasks and active HTTP requests.
- Added `DownloadTask.browserContextJSON` for persistable, redacted/non-sensitive context, while retaining full sensitive headers only in `DownloadCoordinator` runtime memory until task completion/failure/removal.
- Updated `HTTPDownloadEngine` so HEAD, range probe, single-stream, and segmented GET requests apply browser context headers while blocking controlled headers such as `Range`, `If-Range`, `Host`, and `Content-Length`.
- Updated task list and inspector source display to use redacted source URLs.
- Updated the Chrome extension manifest and background worker to capture recent request method, selected request headers, referrer, user agent, final/original URLs, and body metadata with `webRequest`; sensitive headers are flagged as sensitive before native messaging.

Verification evidence:

- `node --check Sources/SwiftGetX/Resources/ChromeExtension/background.js` passed.
- Focused tests passed: `swift test --filter NativeMessageHost --filter HTTPDownloadEngine --filter persistsOnlySafeBrowserContext` with 33 tests across NativeMessageHost, HTTPDownloadEngine, and Torrent files.
- `swift test` passed with 84 tests across 12 suites.
- New tests verify native handoff payload context fetch, HTTP request application of Authorization/Referer/User-Agent/Accept-Language headers while blocking browser-supplied `Range`, and persistence/display redaction that excludes Authorization/Cookie and redacts token-like URL query values.

Remaining risk:

- Chrome now requests `webRequest` plus `<all_urls>` host permissions so it can capture request headers; this is functionally necessary for authenticated downloads but increases extension permission surface. Later takeover-policy work should expose user-facing controls for which sites/headers are forwarded.
- POST/body replay is not implemented in this task; only method and body metadata are carried. Actual POST retry/download support remains for later per-task request configuration work.
- Sensitive headers are retained in memory only for active runtime requests and are dropped on completion/failure/removal; restart/resume of authenticated downloads will need a Keychain or short-lived session strategy in later tasks.

Next step:

- Task 3: Browser Diagnostics and Multi-Browser State.

## Task 3: Browser Diagnostics and Multi-Browser State

Status: [x]

Replace static browser readiness UI with live diagnostics for native host, extension IDs, manifest paths, supported Chromium variants, and app/native-host compatibility. Extend registrar/discovery for Edge, Brave, Vivaldi, Arc, Chromium, and Chrome Canary where local path conventions are known.

Work performed:

- Extended Chromium discovery defaults to include Chrome Canary, Microsoft Edge, Brave, Vivaldi, Arc, Chromium, and Atlas alongside Chrome, with known macOS user-data and NativeMessagingHosts path conventions.
- Added `ChromeNativeHostBrowserDiagnostic` and registrar-level per-browser diagnostics for browser profile presence, discovered extension IDs, paired extension IDs, manifest paths, Native Host executable paths, allowed origin counts, repairability, and supported browser-name checks.
- Updated native host registration diagnostics to preserve per-browser manifest targets and support multiple Chromium-family manifest directories in one register/repair pass.
- Updated `NativeHostDiagnostics` to carry browser diagnostic snapshots, configured/detected/supported counts, sidebar summaries, and smarter manifest reveal target selection.
- Replaced the settings page’s hardcoded “Chrome Native Host” row with live browser diagnostics listing each supported browser, extension IDs, manifest path, native host path, allowed origin count, and status.
- Replaced the sidebar’s static browser-readiness copy with a live Native Host diagnostic status panel.
- Updated browser setup handling so supported Chromium-family setup requests are accepted instead of being gated to exactly “Chrome”, and localized the pairing/rejection messages generically.
- Added English and Simplified Chinese localization for browser diagnostics and generic browser pairing.
- Added focused tests for default Chromium variant paths, per-browser diagnostics, supported browser checks, and writing manifests to multiple browser-specific NativeMessagingHosts directories.

Verification evidence:

- `swift test --filter ChromeExtensionDiscovery --filter ChromeNativeHostRegistrar` passed with 21 tests across 2 suites.
- `swift test` passed with 88 tests across 12 suites.
- `git diff --check` passed.
- Static search confirmed the old static sidebar readiness key is no longer used by app UI code, and the new browser diagnostics keys are present in both localizations.

Remaining risk:

- Safari remains a resource/template path and Firefox requires a separate Native Messaging registrar with different manifest fields and install locations; both are explicitly later-plan work rather than this Chromium-family diagnostics task.
- Browser display rows are SwiftUI/static-inspected and covered by app compilation, but not screenshot-tested in this session.

Next step:

- Large Check 1: Browser Takeover Foundation.

## Large Check 1: Browser Takeover Foundation

Status: [x]

Review requirement drift, native-host failure modes, extension rollback behavior, deep-link security, build/test status, and docs for Tasks 1-3. Fix discovered issues before marking complete.

Work performed:

- Audited Tasks 1-3 against the browser takeover section of `Docs/FunctionalImprovementOpportunities.md`, covering native-host ack semantics, extension fallback/cancel behavior, authenticated context transfer, tokenized localhost payload handoff, diagnostics visibility, Chromium variant registration, and localization.
- Verified that the Chrome extension only cancels/erases browser downloads after a positive native-host/App decision and falls back to Chrome download on native-host runtime error, rejection, timeout, or unexpected exception.
- Added short-lived expiry metadata to native handoff ack deep links and propagated it from `SwiftGetXNativeHost` through `DeepLinkBuilder` and `DeepLinkParser`.
- Added `PendingNativeHandoffPolicy` to reject expired native handoffs and to reject an existing pending confirmation if a newer handoff replaces it before the user responds.
- Updated App and new-task confirmation handling so expired handoffs are rejected before payload fetch/task creation and before confirmed Add creates tasks, and superseded handoffs immediately notify the native host instead of waiting for the timeout.
- Added focused tests for preserving handoff expiry through deep links, rejecting expired handoffs, and rejecting superseded pending handoffs.

Verification evidence:

- `node --check Sources/SwiftGetX/Resources/ChromeExtension/background.js` passed.
- `swift test --filter NativeMessageHost --filter ChromeExtensionDiscovery --filter ChromeNativeHostRegistrar --filter HTTPDownloadEngine` passed with 56 tests across 4 suites.
- `swift test` passed with 91 tests across 12 suites.
- `git diff --check` passed.
- Static inspection confirmed the extension download takeover path calls `suggest()` fallback unless `sendToSwiftGetX` returns `ok`, and only then calls Chrome `downloads.cancel` and `downloads.erase`.

Remaining risk:

- Native handoff expiry is enforced in App-side handling and confirmation actions, but the public `swiftgetx://download` surface still needs the broader payload length, scheme, task-count, and trusted-source validation scheduled in Task 4.
- The ack timeout remains fixed at 60 seconds; later takeover policy work should make timeout and user-facing fallback behavior more configurable.
- Browser extension rollback was verified by static inspection and tests around native-host decisions, not by end-to-end Chrome automation.

Next step:

- Task 4: Deep-Link Safety and Payload Limits.

## Task 4: Deep-Link Safety and Payload Limits

Status: [x]

Add safety limits and validation for public `swiftgetx://download` links: task count, URL length, dangerous schemes/characters, multi-link confirmation defaults, and trusted/native-host handoff distinction. Add tests for malicious or oversized payloads.

Work performed:

- Added `DownloadDeepLinkPolicy` to validate `swiftgetx://download` payload length, parsed task count, allowed source types, dangerous top-level schemes, control characters, and bidirectional override characters.
- Added deep-link trust metadata to `DownloadDraft`, including public-vs-native handoff state, parsed source count, confirmation requirements, and native-handoff acknowledgment eligibility.
- Updated `DeepLinkParser.downloadDraft` to reject duplicate or invalid `url` parameters, swallow invalid download deep links instead of falling through to generic task creation, and strip browser/native metadata from ordinary public links.
- Changed public download deep links, including multi-link and local torrent/file URL drafts, to default to the new-task confirmation sheet rather than automatic task creation.
- Kept trusted native-host handoffs distinct by requiring complete, unexpired ack metadata from known extension/native-host source labels, while preserving expired native handoffs only long enough to reject them back through the ack channel.
- Updated native-host payload creation to always provide a token-protected context payload for native handoffs, even when the browser message contains only legacy top-level fields.
- Updated new-task confirmation and pending-handoff policy so only eligible native handoffs are acknowledged, while browser takeover confirmation semantics still report confirmation to the native host.
- Added deep-link tests for public confirmation defaults, bounded multi-link payloads, local torrent confirmation, oversized payloads, too many tasks, dangerous schemes, control/bidi characters, duplicate URL parameters, incomplete ack metadata, expired handoffs, known native sources, and unknown forged ack-looking sources.

Verification evidence:

- `swift test --filter NativeMessageHost` passed with 28 tests in 1 suite.
- `swift test` passed with 104 tests across 12 suites.
- `git diff --check` passed.

Remaining risk:

- The native-source allow list is intentionally scoped to the extension source labels currently emitted by the bundled Chrome extension. Future extension scanning/takeover work must update this list or replace it with a stronger signed/IPC identity model if new source labels or payload paths are added.
- Public local torrent/file URL deep links are confirmation-only rather than rejected, matching the plan guidance, but they still rely on the user reviewing the confirmation sheet before adding.

Next step:

- Task 5: Extension Scanning and Takeover Rules.

## Task 5: Extension Scanning and Takeover Rules

Status: [x]

Improve extension scanning and takeover control: partial candidate selection, site/file-type/size rules, visible popup errors, and fallback when payloads exceed deep-link length. Prefer native messaging for large payloads or temporary JSON handoff where appropriate.

Work performed:

- Added extension takeover policy controls for allowed/blocked extensions, blocked host fragments, minimum takeover size, static/page-like MIME rejection, short-lived "download in browser" bypasses, and context-menu browser fallback.
- Expanded page scanning to collect normal links, download-attribute links, media/source URLs, HLS/DASH manifests, magnet links, and download-hint links, then enrich candidates through background HEAD/range probes for content type, length, disposition, and final URL.
- Reworked the popup scan result list to support per-candidate selection, select-all/select-none, selected-count display, metadata labels, localized strings, and a visible last-error panel populated from background storage.
- Persisted extension/native-host errors in local storage for popup visibility and cleared them on successful sends.
- Carried full multi-link handoff source text in the token-protected native payload while keeping it out of persisted browser context.
- Added `payloadSource=1` deep-link metadata and native-host preview-source fallback so multi-line, oversized, or large candidate-set handoffs use the native payload source instead of embedding unsafe or overlong source text in the public deep link.
- Updated App handling to replace preview deep-link source text with fetched payload source text for trusted native handoffs, and reject payload-required handoffs when payload recovery fails.
- Added tests for payload-required native deep links, multi-line handoff source preservation, payload context fetches with handoff source text, and non-persistence of sensitive handoff source text.

Verification evidence:

- `node --check Sources/SwiftGetX/Resources/ChromeExtension/background.js` passed.
- `node --check Sources/SwiftGetX/Resources/ChromeExtension/popup.js` passed.
- Node JSON parsing passed for `Sources/SwiftGetX/Resources/ChromeExtension/_locales/en/messages.json` and `Sources/SwiftGetX/Resources/ChromeExtension/_locales/zh_CN/messages.json`.
- `swift test --filter NativeMessageHost` passed with 30 tests in 1 suite.
- `swift test --filter persistsOnlySafeBrowserContext` passed with 1 test in 1 suite.
- `swift test` passed with 106 tests across 12 suites.
- `git diff --check` passed.

Remaining risk:

- Extension candidate enrichment uses best-effort browser `fetch` probes; CORS, authentication, servers that reject HEAD/range, or slow responses can still limit metadata, but candidates fall back to URL/title-based classification.
- Takeover allow/block lists and minimum size are stored as extension local options but do not yet have a full settings UI in the macOS app; later settings work should surface these policies coherently with app-side rules.
- Native payload source recovery is available only for trusted native handoffs with a live localhost payload server; public deep links remain bounded and confirmation-only by design.

Next step:

- Task 6: HTTP Metadata and Content-Disposition.

## Task 6: HTTP Metadata and Content-Disposition

Status: [x]

Parse `Content-Disposition` (`filename*` and `filename`), MIME type, final URL, redirect/source metadata, and server support details. Use this metadata in task creation and tests.

Work performed:

- Added `HTTPResponseMetadata` and `HTTPRedirectMetadata` for persisted HTTP response details including original/final/source-page URLs, MIME type, Content-Disposition, server, resumability, content length, validators, and redirect hops with URL redaction.
- Added a Content-Disposition parser that prefers RFC-style `filename*` over `filename`, percent-decodes UTF-8/Latin-1 values, handles quoted semicolons/escapes, strips path components, and sanitizes unsafe/control/bidi filename characters.
- Extended `DownloadTask`, `DownloadRequest`, and `DownloadSnapshot` so HTTP metadata flows from task creation through active engine snapshots into persisted task records.
- Updated HTTP probing and GET paths to record HEAD/range/GET metadata, final URL, redirects, content type, server, validators, resumability, and Content-Disposition filename.
- Updated fresh HTTP downloads to rename the task/save path to the server-suggested Content-Disposition filename before writing temp files, while leaving partial/resumed downloads on their existing path.
- Updated source display fallback to use redacted final URL metadata when browser context is unavailable.
- Reused `SourceParser.sanitizeFilename` for suggested filenames and extended it to remove control characters.
- Added local HTTP fixture coverage for Content-Disposition filename precedence, final saved filename, MIME/server/content length/validator metadata, redirect metadata, parser safety, and metadata JSON persistence/redaction.

Verification evidence:

- `swift test --filter HTTPDownloadEngine --filter TorrentFileTests` passed with 27 tests across 2 suites.
- `swift test` passed with 110 tests across 12 suites.
- `git diff --check` passed.

Remaining risk:

- The new SwiftData field is an optional JSON field, which should be lightweight for app-side schema evolution, but an installed-user migration was not exercised in this task.
- Server Content-Disposition filenames are used for fresh downloads and can supersede the initial URL/browser-suggested filename. Partial downloads keep their existing path to avoid orphaning temp data.
- Redirect capture records the URLSession-observed redirect hops for the current probe/download request; it is not yet exposed in a dedicated inspector UI beyond persisted metadata.

Next step:

- Large Check 2: Browser and HTTP Metadata.

## Large Check 2: Browser and HTTP Metadata

Status: [x]

Review Tasks 4-6 for security, parser correctness, localization, tests, and compatibility with existing download flows. Run targeted tests and fix issues.

Work performed:

- Audited Tasks 4-6 across deep-link validation, trusted native payload recovery, Chrome extension scan/takeover flow, popup error localization, browser-context persistence, `Content-Disposition` parsing, HTTP redirect metadata, and fresh-vs-resumed download filename handling.
- Found that trusted native payload source text fetched from the localhost handoff server was only parsed before replacing the deep-link preview source. Added `DownloadDeepLinkPolicy.validationForTrustedPayloadSource` so native payload text is bounded, rejects control/bidi characters, rejects dangerous top-level schemes, requires allowed source schemes, and caps scanner batches at 100 sources.
- Updated `SwiftGetXApp.applyPayloadSource` to use the trusted payload validator before mutating the draft source and source count.
- Found that browser/context-provided suggested filenames could be persisted into HTTP response metadata without the same filename hardening used for server `Content-Disposition`. Added model-level suggested filename sanitization in `HTTPResponseMetadata`, including control-character, path-separator, illegal filename, empty, `"."`, `".."`, and bidirectional override handling.
- Added focused regression tests for trusted native payload source bounds/unsafe text and HTTP metadata suggested filename sanitization.
- Confirmed the Chrome extension takeover path still only cancels/erases Chrome downloads after `sendToSwiftGetX` returns `ok`; native-host runtime errors, app rejection, and unexpected exceptions still fall back to Chrome download.
- Confirmed extension scan/popup JavaScript and localization JSON remain syntactically valid.

Verification evidence:

- `node --check Sources/SwiftGetX/Resources/ChromeExtension/background.js` passed.
- `node --check Sources/SwiftGetX/Resources/ChromeExtension/popup.js` passed.
- Node JSON parsing passed for `Sources/SwiftGetX/Resources/ChromeExtension/_locales/en/messages.json` and `Sources/SwiftGetX/Resources/ChromeExtension/_locales/zh_CN/messages.json`.
- `swift test --filter NativeMessageHost --filter HTTPDownloadEngine --filter TorrentFileTests` passed with 60 tests across 3 suites.
- `swift test` passed with 113 tests across 12 suites.
- `git diff --check` passed.

Remaining risk:

- Extension metadata enrichment remains best-effort and can be limited by CORS, authentication, HEAD/range rejection, or slow servers; candidates still fall back to URL/title-based classification.
- Browser extension filename parsing is intentionally lightweight, but Swift now re-sanitizes persisted HTTP metadata filenames before they can affect task naming or save paths.
- End-to-end browser automation against a real installed extension/native host was not run in this check; behavior was verified by static inspection, native-host/deep-link tests, and app-side HTTP tests.

Next step:

- Task 7: HTTP New-Task Preview.

## Task 7: HTTP New-Task Preview

Status: [x]

Add HTTP HEAD/Range metadata preview before creating tasks, including filename, size, resumability, final URL, content type, duplicate-file strategy, and failure fallback.

Work performed:

- Added `HTTPMetadataPreviewService` for HTTP/HTTPS new-task previews. It validates source URLs, probes server metadata with HEAD plus Range fallback, builds preview display names from `Content-Disposition`, browser suggestions, final URLs, or source URLs, and falls back safely when metadata is unavailable.
- Extracted shared HTTP probing/request creation into `HTTPMetadataProbe` and `HTTPRequestFactory` so previews and real downloads use consistent browser-context headers, redirect capture, resumability, response metadata, and timeout behavior.
- Extended `TorrentMetadataPreview` as the shared source-preview model for HTTP metadata, resumability, planned save path, duplicate-file strategy, and browser context.
- Updated `NewTaskSheet` to fetch HTTP metadata previews before Add, refresh when save path/browser context changes, display HTTP resume/type/final URL/duplicate/save-path details, and create tasks from complete previews instead of losing preview metadata.
- Updated `DownloadCoordinator.add(previews:)` to preserve HTTP preview save paths, resumability, response metadata, safe persisted browser context, and runtime browser context where a model context is available.
- Hardened preview and persisted HTTP suggested filenames to use basename-only inputs before sanitization, preventing directory-like browser suggestions from affecting display or save paths.
- Added English and Simplified Chinese localization for HTTP preview details and the generic source-preview loading state.
- Added focused tests for HTTP preview metadata success, HEAD-to-Range fallback, metadata-unavailable fallback, invalid-source fallback sanitization, coordinator task creation from HTTP previews, and basename filename sanitization.

Verification evidence:

- `swift test --filter HTTPDownloadEngine` passed with 28 tests in 1 suite.
- `swift test` passed with 118 tests across 12 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.

Remaining risk:

- HTTP preview metadata remains best-effort: servers can reject HEAD/Range probes, hide metadata behind authentication, or return misleading headers. In those cases the UI falls back to a safe name/path preview and creates a normal HTTP task.
- Duplicate handling is currently shown as "Available" or automatic rename to match the existing `FileManager.uniqueFileURL` finalization behavior. User-selectable overwrite/skip/ask policies remain for later settings/per-task option work.
- Browser-context sensitive headers are still runtime-only; previews can use live context, but persisted created tasks keep only safe context.
- SwiftUI preview details were build-verified and covered through model/coordinator tests, but not screenshot-tested in this session.

Next step:

- Task 8: Per-Task Download Options and Persistent Speed Settings.

## Task 8: Per-Task Download Options and Persistent Speed Settings

Status: [x]

Add per-task overrides for segment count, retry limit, speed limit, save path, filename, and headers. Ensure toolbar speed-limit changes persist through `AppSettings` or are explicitly modeled as temporary limits.

Work performed:

- Added `HTTPDownloadOptions` with bounded segment/retry overrides, per-task download limit, sanitized filename override, additional HTTP headers, controlled-header filtering, and persistable redaction for sensitive headers.
- Persisted safe HTTP options on `DownloadTask` while keeping full runtime HTTP options in `DownloadCoordinator` memory for active authenticated/header-bearing tasks.
- Updated new-task HTTP flows so the sheet exposes filename, segment count, retry count, per-task speed, and headers; preview refreshes use those options; and created HTTP tasks preserve preview save paths plus selected options.
- Updated HTTP probing and downloading so per-task segment/retry overrides, per-task speed limiting, filename override, and additional headers apply consistently to preview, HEAD/range probes, single-stream downloads, and segmented downloads.
- Connected toolbar speed-limit choices to `AppSettings` persistence through `DownloadCoordinator.setSpeedLimit(..., persistsToSettings: true)`.
- Added English and Simplified Chinese localization for the HTTP options editor and removed duplicate localization keys during verification cleanup.
- Added tests for safe HTTP option persistence, per-task segment/retry/header behavior, filename override/header application, and toolbar speed persistence.

Verification evidence:

- `swift build` passed.
- `swift test` passed with 127 tests across 13 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static search confirmed each `http_options_*` localization key appears once per localization file after cleanup.

Remaining risk:

- Per-task segment/retry/speed options are applied when a download starts; changing those options for an already-running task is not yet a live runtime adjustment path.
- Sensitive per-task headers are intentionally memory-only and are not available after app restart unless the user re-enters them or a later secure storage design is added.
- The UI supports one filename override for a single HTTP source; multi-link batches share common HTTP transfer options and keep per-item names from metadata/source parsing.
- SwiftUI behavior was build-verified and covered through model/engine/coordinator tests, but not screenshot-tested in this session.

Next step:

- Task 9: Queue Scheduling and Restart Policy.

## Task 9: Queue Scheduling and Restart Policy

Status: [x]

Implement queue ordering/reordering, priority, automatic queue fill when concurrency increases, failed-task backoff/requeue behavior, restart policy for incomplete tasks, and remove or replace fixed 500-task assumptions where they affect scheduling/statistics.

Work performed:

- Added persistent queue metadata to `DownloadTask`: queue position, priority, failure count, and next retry time, plus queue-priority display helpers and queue-sort helpers.
- Added restart/requeue settings to `AppSettings` and `AppSettingsRecord`, including restart policy, automatic failed-task requeue, and retry-limit persistence.
- Reworked `DownloadCoordinator` scheduling to sort all tasks by active state, queue priority, queue position, status, and creation date; removed the fixed 500-task fetch cap from coordinator task retrieval.
- Added queue reordering APIs for move-to-top, move-up, move-down, and priority changes, with queue position rewriting and localized task logs.
- Changed resume behavior to queue tasks first, then fill available slots through the scheduler, so concurrency limits are respected.
- Added automatic queue fill on settings reload/concurrency increases, delayed queue wakeups for failed-task retry backoff, retry-limit handling, and restart policy handling for running/seeding/verifying tasks.
- Assigned queue positions to newly added tasks and normalized existing zero/missing positions on coordinator attach.
- Surfaced queue restart/retry settings in Settings and queue move/priority controls in task context menus; sorted the main task list through coordinator queue ordering.
- Added English and Simplified Chinese localization for queue settings, priorities, actions, and logs.
- Added coordinator tests covering large task sets beyond 500, priority/position scheduling, concurrency increase slot fill, failed-task backoff/retry limit, restart auto-resume, and queue move/priority ordering.

Verification evidence:

- `swift test --filter DownloadCoordinator` passed with 7 tests in the `DownloadCoordinator` suite.
- `swift test` passed with 133 tests across 13 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.

Remaining risk:

- Queue reordering is exposed through explicit context-menu actions rather than drag-and-drop; drag/drop remains a later UI improvement if the plan still requires it after Large Check 3.
- Failed authenticated HTTP tasks can be requeued, but sensitive runtime-only browser/per-task headers are still unavailable after app restart by design until a secure storage strategy exists.
- SwiftUI queue controls were compile/test verified and statically inspected, not screenshot-tested in this session.

Next step:

- Large Check 3: HTTP Task Control.

## Large Check 3: HTTP Task Control

Status: [x]

Review Tasks 7-9 for data migration, settings consistency, user-facing behavior, scheduler edge cases, and tests. Run `swift test` if Swift code changed.

Work performed:

- Audited Tasks 7-9 against the HTTP/task-control portions of `Docs/FunctionalImprovementOpportunities.md`, covering HTTP preview metadata, per-task HTTP options, AppSettings persistence, queue ordering, restart/requeue policy, large-list behavior, task-list controls, toolbar behavior, and menu/command paths.
- Found that global Pause All / Resume All still respected the current sidebar filter and search text. Updated them to operate on `allTasks()` so menu and command actions affect the full queue as labeled.
- Found that pausing/cancelling/removing an active task did not deterministically refill the next queued slot until later engine snapshots. Added slot-fill scheduling after active pause/cancel/remove engine control paths.
- Found that the toolbar and task-row controls treated queued/verifying inconsistently. Updated controls so verifying tasks show/use pause, while queued tasks show/use resume/start queue semantics.
- Added a narrow `DownloadCoordinator(runsEngines:)` test seam so coordinator queue tests can verify scheduling state without spawning real HTTP engine work.
- Added regression tests for queue-policy settings persistence, active pause/cancel/remove slot refill, and global pause/resume ignoring current filter/search.

Verification evidence:

- `swift test --filter DownloadCoordinator` passed with 12 tests in the `DownloadCoordinator` suite.
- `swift build` passed.
- `swift test` passed with 138 tests across 13 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.

Remaining risk:

- Drag-and-drop queue reordering, planned task windows, and network/power-aware scheduling remain deferred beyond Tasks 7-9 and are not implemented in this check.
- Failure-recovery UX items such as a distinct cancelled state, copy-error/reprobe actions, disk/permission preflight, and partial-file operations are intentionally Task 10 scope.
- SwiftUI control behavior was compile/test verified and statically inspected, not screenshot-tested.

Next step:

- Task 10: Failure Recovery, Cancellation, and File Preflight.

## Task 10: Failure Recovery, Cancellation, and File Preflight

Status: [x]

Add a distinct cancelled state, retry/copy-error/reprobe/rename-and-continue actions, HTTP status-specific user messages, disk-space and permission preflight, and clear retain/delete/open partial-file operations.

Work performed:

- Added `DownloadStatus.cancelled` across the model, filters, task list, inspector, and menu-bar snapshot/controller paths, including queue-manageable/terminal semantics and Resume All support.
- Updated cancellation and retry handling so user-cancelled tasks keep a distinct cancelled state, clear queue failure/backoff state, refill freed queue slots, and ignore stale late engine snapshots except for preserving higher downloaded byte counts.
- Added HTTP failure recovery actions for retry, copy error, reprobe metadata, rename-and-continue, and retain/open/reveal/delete partial data, with context-menu wiring and localized English/Simplified Chinese strings.
- Added `HTTPPartialDataStore` to centralize single-part, segmented, and merge-file partial data discovery, byte accounting, removal, and continuation-path moves.
- Changed HTTP task removal so task-only removal retains partial HTTP data, while explicit file deletion removes final and partial local data.
- Added HTTP local preflight checks for missing destination folders, parent path type, destination directory conflicts, write permissions/probe writes, and available disk capacity before network requests.
- Added status-specific HTTP error messages for 401, 403, 404, 416, 429, and 5xx responses, and kept 416/range fallback behavior where appropriate.
- Added regression tests for cancelled queue behavior, retry recovery, stale snapshot protection, partial-data retain/delete/rename/remove semantics, HTTP preflight failure, status-specific HTTP failures, and menu-bar cancelled counts/status priority.

Verification evidence:

- `swift test --filter DownloadCoordinator` passed with 16 tests in the `DownloadCoordinator` suite.
- `swift test --filter HTTPDownloadEngine` passed with 39 tests in the `HTTPDownloadEngine` suite.
- `swift test --filter MenuBarSnapshot` passed with 4 tests in the `MenuBarSnapshot` suite.
- `swift test` passed with 147 tests across 13 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.

Remaining risk:

- Partial-file open/reveal actions use `NSWorkspace` and were compile-verified plus covered indirectly by partial-data discovery tests, but not UI-automated.
- Disk capacity preflight depends on macOS volume capacity APIs; insufficient-space behavior is implemented but not forced in tests because reliably exhausting a volume is not safe in this workflow.
- Rename-and-continue currently chooses a continuation filename such as `file 2.ext` and moves partial HTTP data there before queueing; broader user-selectable conflict policies remain future settings/UI work.

Next step:

- Task 11: SwiftGetXTorrentCore Target and Metadata Parsers.

## Task 11: SwiftGetXTorrentCore Target and Metadata Parsers

Status: [x]

Create `SwiftGetXTorrentCore` and implement/test bencode, canonical info bytes, v1 info hash, single/multi-file metainfo, announce-list/private flag parsing, and magnet parsing for hex/base32 `btih`, `dn`, `tr`, and `xl`.

Work performed:

- Added a new pure Swift `SwiftGetXTorrentCore` target and library product, and wired it into the app/test target dependencies without changing the optional libtorrent path.
- Implemented strict bencode parsing with byte-string, integer, list, and dictionary support, canonical dictionary key ordering checks, trailing-data detection, canonical integer/length validation, and deterministic re-encoding.
- Implemented `TorrentMetainfo` parsing for BitTorrent v1 `.torrent` files, including retained canonical `info` dictionary bytes, SHA-1 v1 info hash, single-file and multi-file file lists, piece length, piece hashes, announce, announce-list tiers, and private flag.
- Implemented `MagnetURI` parsing for `btih` hex/base32 info hashes, display name (`dn`), repeated tracker (`tr`) values, and exact length (`xl`).
- Moved torrent file metadata parsing ownership out of `TorrentMetadataService` and into `SwiftGetXTorrentCore`, leaving the app service responsible only for caching/preview mapping into existing `TorrentFile` rows.
- Added deterministic unit tests for valid/invalid bencode, canonical info bytes and known SHA-1 hashes, single/multi-file metainfo, announce-list/private metadata, invalid metainfo, and magnet hex/base32 parsing.

Verification evidence:

- `swift test --filter SwiftGetXTorrentCore --filter TorrentMetadataService` passed with 11 tests across 2 suites.
- `swift build` passed.
- `swift test` passed with 153 tests across 14 suites.
- `git diff --check` passed.

Remaining risk:

- Task 11 intentionally covers metadata parsing only. Path traversal, duplicate path detection, path length/control-character policy, and resume schema are still Task 12 scope.
- The new parser validates canonical bencode and BEP 3 v1 metadata required by the Swift core, which is stricter than the previous lightweight preview parser; malformed or incomplete torrent fixtures now fail earlier.
- Magnet metadata fetching over peers remains unavailable in this task; this only parses magnet URI parameters and info hashes.

Next step:

- Task 12: Torrent Path Layout and Resume Schema.

## Task 12: Torrent Path Layout and Resume Schema

Status: [x]

Implement `TorrentContentLayout` with explicit save directory, content root, file paths, offsets, lengths, priorities, path traversal protection, duplicate path detection, control-character/length checks, and a pure Swift resume-state schema.

Work performed:

- Added `TorrentContentLayout`, `TorrentContentFile`, and `TorrentContentPriority` to `SwiftGetXTorrentCore` for pure Swift torrent file mapping with explicit save directory, output name, content root, final file URL for single-file torrents, per-file URLs, offsets, lengths, and priorities.
- Preserved raw torrent path components in `TorrentFileInfo` and added `TorrentMetainfo.isMultiFile`/`isSingleFile` so layout code can distinguish single-file torrents from multi-file torrents that happen to contain one file.
- Added layout validation for missing files, non-contiguous file indexes, unsafe path components, absolute/root-like paths, `..`, empty components, slash/backslash injection, control/bidi characters, per-component and full-path byte limits, duplicate path collisions, and total-length overflow.
- Added `TorrentCoreResumeState` and supporting resume schema types for completed piece bitsets, partial blocks, file modification/fingerprint checks, tracker state, peer ban list, schema versioning, info-hash/layout validation, and stable JSON encode/decode with decode-time validation.
- Added focused torrent-core tests for safe single/multi-file layouts, one-file multi-file torrents, offsets, priorities, content root/final file paths, unsafe/malicious paths, duplicate paths, and resume-state round trips plus invalid piece/block/version/hash/layout cases.

Verification evidence:

- `swift test --filter SwiftGetXTorrentCore` passed with 16 tests in 1 suite.
- `swift build` passed.
- `swift test` passed with 161 tests across 14 suites.
- `git diff --check` passed.

Remaining risk:

- Task 12 establishes the pure Swift layout and resume-state model, but it does not yet replace libtorrent runtime resume data or wire the layout into a running Swift torrent engine. That remains Task 14+ and peer/storage tasks.
- Task 13 still needs app-level BT save path semantics and deletion boundary work so UI/model paths and local delete confirmations use the new layout consistently.
- Disk-space preflight and sandbox boundary checks for actual torrent storage writes remain in later storage/filesystem tasks.

Next step:

- Large Check 4: Torrent Metadata Foundation.

## Large Check 4: Torrent Metadata Foundation

Status: [x]

Review Tasks 10-12 for data-model migrations, path safety, parser limits, tests, and docs. Confirm no release dependency on libtorrent was added.

Work performed:

- Audited Tasks 10-12 against the failure-recovery and torrent-metadata sections of `Docs/FunctionalImprovementOpportunities.md`, including cancelled-state/file-retention behavior, pure Swift torrent metadata parsing, content layout, resume schema, path safety, parser limits, and optional libtorrent boundaries.
- Confirmed `SwiftGetXTorrentCore` remains a pure Swift support target with only `Foundation`/`CryptoKit` imports and no SwiftUI, SwiftData, AppKit, Network, or `CSwiftGetXLibtorrent` coupling.
- Confirmed default release builds still do not require libtorrent; `Package.swift` keeps `CSwiftGetXLibtorrent` behind `SWIFTGETX_ENABLE_LIBTORRENT=1`, and the Swift torrent core has no libtorrent references.
- Hardened bencode parsing with explicit input-size, nesting-depth, collection-count, and byte-string-length limits.
- Applied the same resource limits to canonical `info` dictionary byte extraction so info-hash calculation cannot bypass parser limits.
- Added torrent metainfo total-length overflow protection and piece-count validation against total length and piece length, rejecting impossible piece coverage.
- Tightened multi-file path parsing so non-string path components fail metadata validation instead of being silently dropped.
- Added full output-file path byte-length validation after combining save directory/content root and relative torrent paths.
- Surfaced parsed `.torrent` and magnet tracker URLs in `TorrentMetadataPreview` and the new-task preview without adding any libtorrent release dependency.
- Added regression tests for bencode resource limits, metainfo limit propagation, mismatched piece coverage, full output-path length rejection, and tracker-list preview data.

Verification evidence:

- `swift test --filter SwiftGetXTorrentCore --filter TorrentMetadataService` passed with 23 tests across 2 suites.
- `swift build` passed.
- `swift test` passed with 165 tests across 14 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static import audit of `Sources/SwiftGetXTorrentCore` found only `Foundation` and `CryptoKit`.
- Static libtorrent audit found no libtorrent references in `Sources/SwiftGetXTorrentCore`; remaining `CSwiftGetXLibtorrent` references are in the existing optional adapter/Package.swift gate.

Remaining risk:

- Task 13 still needs app-level BT save path semantics and local deletion-boundary work so single-file and multi-file torrent UI/model paths cannot remove the wrong content.
- The pure Swift torrent core is still metadata/layout/resume-state only; runtime Swift torrent adapter, tracker, peer, storage, and piece verification work begins in Task 14+.
- Optional libtorrent docs/release cleanup remains later release/distribution scope; this check only confirmed no new release dependency was added.

Next step:

- Task 13: BT Save Path Semantics and Deletion Boundaries.

## Task 13: BT Save Path Semantics and Deletion Boundaries

Status: [x]

Split or clarify BT save directory, output name, final file path/content root path, UI display paths, and local deletion confirmation so single-file and multi-file torrents cannot delete the wrong directory or miss actual content.

Work performed:

- Added explicit persisted torrent path metadata on `DownloadTask`: save directory, output name, content root path, and final single-file path.
- Wired torrent task creation and preview planning through `TorrentContentLayout`, so app-level `savePath` now remains the libtorrent/engine save directory while UI surfaces the concrete final file path or multi-file content root.
- Extended `DownloadRequest` and `TorrentStartRequest` so torrent engines receive save directory separately from output name, content root path, and final file path.
- Updated task list, inspector, menu bar snapshot/reveal behavior, and new-task previews to use torrent display paths instead of the raw save directory.
- Bounded local torrent deletion to exact known content paths inside the save directory. Unknown/legacy torrent tasks without exact content metadata now skip local file deletion rather than deleting a broad save directory.
- Updated delete confirmations and localization to show the concrete path(s) that will be removed, or a no-known-content warning.
- Added regression tests for single-file and multi-file torrent path persistence, exact-path deletion boundaries, unresolved torrent deletion safety, and the engine request boundary.

Verification evidence:

- `swift test --filter DownloadCoordinator --filter TorrentDownloadEngine --filter TorrentMetadataService` passed with 32 tests across 3 suites after rerunning with SwiftPM cache access.
- `swift build` passed.
- `swift test` passed with 169 tests across 14 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.

Remaining risk:

- Existing installed SwiftData stores were not migration-tested in this task; the new torrent path fields are optional and old torrent tasks intentionally avoid local deletion unless exact content metadata is known.
- Unknown magnet tasks without metadata show only the save directory/output name in preview and confirmation safety text until runtime metadata/layout is available in later torrent-engine work.
- Runtime Swift torrent adapter, storage writes, and live metadata layout updates remain Task 14+ scope.

Next step:

- Task 14: Swift Torrent Adapter Skeleton and Engine Status.

## Task 14: Swift Torrent Adapter Skeleton and Engine Status

Status: [x]

Add `SwiftTorrentEngineAdapter` behind the existing `TorrentEngineAdapter` boundary, expose engine type/status in UI/settings, keep libtorrent optional, and wire metadata/layout preview without requiring libtorrent.

Work performed:

- Added a pure Swift `SwiftTorrentEngineAdapter` behind `TorrentEngineAdapter`, defaulting torrent runtime to the Swift metadata/layout skeleton without requiring libtorrent.
- Extended torrent runtime options, connection info, and health info with `TorrentEngineKind` and `TorrentEngineStatus`, including legacy JSON decode defaults for existing persisted task records.
- Added adapter identity/status to the adapter boundary so Swift reports `metadataOnly`, compiled libtorrent reports `available`, and missing libtorrent reports `unavailable` without silently falling back to Swift.
- Wired the Swift adapter to parse local `.torrent` metadata through `SwiftGetXTorrentCore`, expose file layout preview data and tracker rows, and report magnet trackers while leaving tracker/peer/storage runtime pending.
- Persisted the selected torrent engine through `AppSettings` and added a BT engine picker plus status copy in Settings.
- Surfaced engine type/status in the Inspector connection and health panels, with metadata-only engines clearly not treated as full DHT/PEX/LSD runtime availability.
- Added English and Simplified Chinese localization for engine labels, statuses, and Swift metadata-only runtime messaging.
- Added tests for app-setting persistence, default Swift adapter status, libtorrent-unavailable identity, Swift metadata-only snapshots, and legacy torrent diagnostic JSON decoding.

Verification evidence:

- `swift test --filter TorrentDownloadEngine --filter TorrentFileTests --filter DownloadCoordinator` passed with 39 tests across 3 suites after rerunning with SwiftPM cache access.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- `swift build` passed after rerunning with SwiftPM cache access.
- `swift test` passed with 174 tests across 14 suites after rerunning with SwiftPM cache access.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; the linker emitted local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 177 tests across 15 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- The Swift torrent adapter is intentionally metadata/layout only. It does not perform tracker announces, peer-wire connections, storage writes, piece verification, or real data transfer until Tasks 15-18.
- Switching the global engine changes the engine used for new/configured runtime starts, but already active torrent handles are not migrated between engines in this skeleton task.
- Optional libtorrent verification depends on the local prebuilt `.build/libtorrent/libtorrent-build/libtorrent-rasterbar.a` archive and Homebrew OpenSSL libraries; this task did not change the C wrapper or vendored native build.

Next step:

- Task 15: Tracker Client and Mock Tracker Tests.

## Task 15: Tracker Client and Mock Tracker Tests

Status: [x]

Implement HTTP and UDP tracker announce basics, compact/non-compact peer parsing, tier scheduling, retry/timeout state, scrape placeholders, diagnostics snapshots, and deterministic local mock tests.

Work performed:

- Added `TorrentTrackerClient` with HTTP announce support, UDP connect/announce support, transaction id validation, timeout/retry handling, and support for compact plus non-compact HTTP peer lists.
- Added `TorrentTrackerScheduler` state tracking with failure backoff, tracker success state, announce timing, and tier-aware candidate selection that rotates through equally eligible trackers by announce recency.
- Added `TorrentTrackerScrape` helpers for announce-to-scrape conversion and scrape result parsing, and normalized scrape parse failures into tracker errors.
- Wired the pure Swift torrent adapter to emit tracker diagnostics snapshots, surface tracker peers, and move through `fetchingPeers` and `connectingPeers` states using the new tracker client.
- Added deterministic local mock tests covering HTTP and UDP tracker announce flows, HTTP retry, transaction id mismatch validation, timeout retry behavior, compact/non-compact peer parsing, scrape parsing, and tracker-aware adapter snapshots.
- Updated task list, toolbar, inspector, menu bar, filtering, and coordinator active-slot handling so the new peer-fetching statuses behave consistently with active torrent work.

Verification evidence:

- `swift build` passed after rerunning with SwiftPM cache access.
- `swift test --filter SwiftGetXTorrentCore --filter TorrentDownloadEngine` passed with 39 tests across 2 suites after rerunning with SwiftPM cache access.
- `swift test` passed with 182 tests across 14 suites after rerunning with SwiftPM cache access.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed after the final tracker-client refinements.
- Static libtorrent audit found no `CSwiftGetXLibtorrent` or `LibtorrentAdapter` references in `Sources/SwiftGetXTorrentCore`; remaining references are limited to the existing optional adapter and `Package.swift` gate.
- Static import audit found no SwiftUI, SwiftData, AppKit, or libtorrent imports in `Sources/SwiftGetXTorrentCore`; the tracker client uses conditional `Network` only for UDP tracker transport.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; the linker emitted local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 185 tests across 15 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- The Swift torrent adapter is still metadata/layout only beyond tracker diagnostics; peer-wire connections, storage writes, piece verification, and end-to-end swarm behavior remain in Tasks 16-18.
- Tracker peers are surfaced as diagnostics only until the peer-wire work lands in Task 16, so `connectingPeers` does not yet mean a peer socket has completed a BitTorrent handshake.
- Optional libtorrent verification depends on the local prebuilt `.build/libtorrent/libtorrent-build/libtorrent-rasterbar.a` archive and Homebrew OpenSSL libraries; this task did not change the C wrapper or vendored native build.

Next step:

- Large Check 5: Swift Torrent Adapter and Tracker.

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
