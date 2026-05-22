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

Status: [x]

Review Tasks 13-15 for adapter isolation, UI compatibility, network input validation, test determinism, and build status.

Work performed:

- Audited Tasks 13-15 against the BitTorrent sections of `Docs/FunctionalImprovementOpportunities.md`, covering BT save-path semantics, exact local deletion boundaries, Swift-vs-libtorrent adapter isolation, tracker announce behavior, tracker diagnostics, and deterministic local tracker tests.
- Confirmed `TorrentEngineAdapter` remains the app/coordinator boundary, with `SwiftTorrentEngineAdapter` providing metadata/layout/tracker diagnostics and optional libtorrent references kept behind the existing `SWIFTGETX_ENABLE_LIBTORRENT` gate.
- Confirmed `SwiftGetXTorrentCore` has no SwiftUI, SwiftData, AppKit, `CSwiftGetXLibtorrent`, or `LibtorrentAdapter` references; its conditional `Network.framework` import is limited to the UDP tracker transport allowed by the plan.
- Audited UI compatibility for `fetchingPeers` and `connectingPeers` across task list, toolbar, inspector, menu bar, filtering, and coordinator active-slot handling.
- Audited network input validation and test determinism around tracker URL schemes, 20-byte info hash and peer id requirements, byte counter validation, HTTP compact/non-compact peer parsing, UDP transaction id mismatch handling, retry behavior, scrape parsing, and mock tracker snapshots.
- No source fixes were needed in this check.

Verification evidence:

- `swift test --filter SwiftGetXTorrentCore --filter DownloadCoordinator --filter TorrentDownloadEngine --filter TorrentMetadataService --filter MenuBarSnapshot` passed with 67 tests across 5 suites.
- `swift build` passed.
- `swift test` passed with 182 tests across 14 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static libtorrent audit found no `CSwiftGetXLibtorrent` or `LibtorrentAdapter` references in `Sources/SwiftGetXTorrentCore`; remaining references are limited to `Sources/SwiftGetX/Services/TorrentDownloadEngine.swift` and `Package.swift` optional gates.
- Static app-framework audit found no SwiftUI, SwiftData, or AppKit imports in `Sources/SwiftGetXTorrentCore`; the only non-Foundation platform framework is conditional `Network` for UDP tracker transport.
- Test fixture audit confirmed Task 13-15 tracker, path, deletion, and adapter tests use deterministic local fixtures or mock transports rather than external tracker or swarm dependencies.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; the linker emitted local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 185 tests across 15 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- The Swift torrent adapter still only reaches tracker diagnostics; peer-wire sockets, storage writes, piece verification, real swarm behavior, and magnet metadata exchange remain Tasks 16-18.
- Tracker peers surfaced in `connectingPeers` are diagnostics from tracker announce responses, not yet completed BitTorrent peer handshakes.
- UI behavior for the new torrent states was compile/test verified and statically inspected, not screenshot-tested.
- Optional libtorrent verification depends on the local prebuilt `.build/libtorrent/libtorrent-build/libtorrent-rasterbar.a` archive and Homebrew OpenSSL libraries.

Next step:

- Task 16: Peer Wire MVP and Torrent Storage.

## Task 16: Peer Wire MVP and Torrent Storage

Status: [x]

Implement minimal TCP peer-wire handshake/messages, request pipeline, block limits, piece SHA-1 validation, single/multi-file storage writes across boundaries, pause/resume/delete partial data, and mock peer tests.

Work performed:

- Added `TorrentPeerWireHandshake`, `TorrentPeerWireMessage`, `TorrentPeerBlockPlanner`, `TorrentPeerWireTCPTransport`, and `TorrentPeerWireSession` in `SwiftGetXTorrentCore` for BitTorrent handshakes, core peer-wire messages, block validation, request pipelining, timeout resend, unchoke gating, and SHA-1 piece validation.
- Added `TorrentPeerWorkspace` and `TorrentContentStorage` for pure Swift torrent resume-state persistence, exact partial-data deletion, and random writes across single-file and multi-file torrent layout boundaries.
- Wired `SwiftTorrentEngineAdapter` beyond tracker diagnostics: it now takes tracker peers, creates peer transports/sessions, downloads sequential pieces through the peer-wire session, writes verified content, saves resume state, and emits running/completed snapshots with downloaded bytes, speed, ETA, peer count, tracker rows, and Swift engine availability.
- Preserved the existing `TorrentEngineAdapter` boundary and kept peer transport injectable so app-level tests can use deterministic mock tracker and peer transports without external network dependencies.
- Added peer-wire and adapter tests for handshake/message framing, block planning, port framing, cross-file storage writes, mock peer single-piece download, invalid piece hash rejection, pause/resume/delete state handling, and end-to-end Swift adapter completion through a mocked tracker peer.
- Hardened the timeout-resend mock peer fixture so timeout recovery is tested after the normal unchoke gate.

Verification evidence:

- `swift test --filter TorrentPeerWire` passed with 7 tests in 1 suite after rerunning with SwiftPM cache access.
- `swift test --filter SwiftGetXTorrentCore --filter TorrentDownloadEngine --filter TorrentPeerWire` passed with 47 tests across 3 suites after rerunning with SwiftPM cache access.
- `swift test` passed with 190 tests across 15 suites after rerunning with SwiftPM cache access.
- `swift build` passed after rerunning with SwiftPM cache access.
- `git diff --check` passed.
- Static audits confirmed `SwiftGetXTorrentCore` still has no SwiftUI, SwiftData, AppKit, `CSwiftGetXLibtorrent`, or `LibtorrentAdapter` imports/references; libtorrent references remain limited to the optional Package.swift gate and existing app adapter boundary.

Remaining risk:

- The Swift torrent runtime is still an MVP path: it uses sequential piece order and the first announced peer. Multi-peer pooling, rarest-first selection, peer scoring, endgame behavior, global/per-task speed limits, and tracker completed/stopped announces remain Task 17 scope.
- Magnet metadata exchange is still unavailable until Task 18, so magnet tasks can parse trackers/info hashes but cannot yet fetch metadata over peer extensions.
- Resume support now persists completed piece state and pause/delete boundaries, but richer sub-piece reuse across process restarts should be revisited when the Task 17 piece manager and peer pool land.

Next step:

- Task 17: Real Swarm MVP and Runtime Snapshots.

## Task 17: Real Swarm MVP and Runtime Snapshots

Status: [x]

Implement multi-peer connection pooling, rarest-first and endgame behavior, peer scoring, global/per-task speed limits, tracker completed/stopped events, and `DownloadSnapshot` mapping for files, peers, trackers, health, speed, ETA, and runtime options.

Work performed:

- Extended the Swift torrent adapter from the single-peer MVP into a bounded peer pool keyed by tracker endpoint, with duplicate endpoint filtering, per-peer session reuse, failure removal, pause/cancel/remove cleanup, and tracker `stopped` announces.
- Added peer runtime scoring for successful pieces, timeouts, bad pieces, and protocol errors, so the adapter retries lower-scored peers and surfaces peer flags/rates in snapshots.
- Added rarest-first/sequential piece ordering and endgame-state detection in `SwiftGetXTorrentCore`, while preserving sequential mode when requested by runtime options.
- Added global/per-task torrent speed-limit handling for download throttling/snapshot capping and upload-limit snapshot mapping.
- Added tracker `completed` announces after successful data completion, while keeping the final Swift adapter status at `completed`; seeding state/policies remain Task 20 scope.
- Expanded torrent snapshot mapping for file progress, peer rows, tracker rows, connection counts, health fields, runtime options, distributed copies, speed, ETA, upload slots, and resume-state save status.
- Added deterministic mock tracker/peer tests for single-file completion, multi-file small-piece writes, bad-peer retry/scoring, runtime snapshot mapping, speed/upload limits, tracker `started/completed/stopped` events, and selector ordering/endgame helpers.
- Corrected a verification regression where the Swift adapter had drifted back to `seeding` on completion; Task 17 now emits `completed` until Task 20 implements real seeding policy behavior.

Verification evidence:

- `swift test --filter SwiftGetXTorrentCore --filter TorrentDownloadEngine --filter TorrentPeerWire` passed with 49 tests across 3 suites after the completion-status correction.
- `swift build` passed.
- `swift test` passed with 192 tests across 15 suites.
- `git diff --check` passed.
- Static libtorrent audit with `rg -n "CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore Sources/SwiftGetX/Services/TorrentDownloadEngine.swift Package.swift` found no libtorrent references in `Sources/SwiftGetXTorrentCore`; remaining matches are the existing optional `Package.swift` gate and app adapter boundary.
- Static core isolation audit with `rg -n "import (SwiftUI|SwiftData|AppKit)|CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore` found no matches.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; the linker emitted the existing local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 195 tests across 16 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- This remains a swarm MVP: pieces are still downloaded one at a time, endgame is represented in runtime state rather than duplicate block requests, and availability is currently inferred from peer count instead of real bitfield/have data.
- Peer scoring is intentionally simple and in-memory; richer peer bans, optimistic unchoke behavior, connection backoff, and long-lived peer statistics remain future torrent runtime work.
- Upload-rate reporting maps configured upload limits only; actual upload/seeding throughput and share ratio accounting remain Task 20.
- Magnet metadata exchange is still unavailable until Task 18, so magnet tasks can parse trackers/info hashes but cannot yet fetch metadata over BEP 9.

Next step:

- Task 18: Magnet Metadata.

## Task 18: Magnet Metadata

Status: [x]

Implement BEP 10 extension handshake and BEP 9 `ut_metadata` exchange, metadata assembly and info-hash verification, fetching-metadata UI state, timeout actions, and mock extended-peer tests.

Work performed:

- Added `TorrentExtensionProtocol` in `SwiftGetXTorrentCore` with BEP 10 extension handshakes, BEP 9 `ut_metadata` request/data/reject message encoding and decoding, metadata piece assembly, size validation, and info-hash verification.
- Extended peer-wire message support for message id 20 extended messages and extension-protocol reserved handshake bits without coupling the core to app UI, SwiftData, AppKit, or libtorrent.
- Added `TorrentMetainfo.parseInfoDictionary(...)` so fetched magnet metadata can become a normal v1 `TorrentMetainfo` after SHA-1 info-hash validation.
- Wired `SwiftTorrentEngineAdapter` so magnet tasks announce trackers, connect to peers, enter `fetchingMetadata`, fetch metadata over BEP 9, refresh in-memory file/layout metadata, and then continue through the existing Swift piece download path.
- Added timeout-visible behavior for magnet metadata fetches: the Swift adapter emits a `fetchingMetadata` snapshot with the timeout error while the metadata fetch continues in the background unless the user pauses/cancels the task.
- Added `fetchingMetadata` status handling across model state, queue/activity accounting, menu bar, toolbar/task controls, task list, inspector colors, localization, and libtorrent status mapping.
- Added deterministic tests for BEP 10/BEP 9 message encoding, mock extended-peer metadata fetch, metadata hash rejection, Swift adapter magnet metadata-to-download completion, timeout-then-continue behavior, and wrong-info-hash adapter failure.

Verification evidence:

- `swift test --filter TorrentPeerWire --filter TorrentDownloadEngine --filter SwiftGetXTorrentCore` passed with 55 tests across 3 suites.
- `swift build` passed.
- `swift test` passed with 198 tests across 15 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static libtorrent audit with `rg -n "CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore Sources/SwiftGetX/Services/TorrentDownloadEngine.swift Package.swift` found no libtorrent references in `Sources/SwiftGetXTorrentCore`; remaining matches are the existing optional `Package.swift` gate and app adapter boundary.
- Static core isolation audit with `rg -n "import (SwiftUI|SwiftData|AppKit)|CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore` found no matches.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; the linker emitted the existing local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 201 tests across 16 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- Magnet metadata fetching currently depends on tracker-discovered peers; trackerless magnet metadata still needs DHT/PEX/LSD work from Task 19.
- BEP 9 requests are sequential and use one peer at a time. Parallel metadata piece requests, peer rotation during a slow exchange, and richer timeout/retry policy remain future runtime hardening.
- Timeout handling now keeps the task in `fetchingMetadata` and leaves pause/cancel available, but richer explicit UI actions such as “copy magnet” or a dedicated “continue waiting” button remain later UX/support-tooling scope.
- A real public magnet was not exercised in this session to keep tests deterministic and avoid external network dependence; local mock extended peers cover the protocol and adapter behavior.

Next step:

- Large Check 6: Peer Wire and Magnet MVP.

## Large Check 6: Peer Wire and Magnet MVP

Status: [x]

Review Tasks 16-18 for protocol safety, storage consistency, piece verification, resume behavior, UI state transitions, and deterministic tests.

Work performed:

- Audited Tasks 16-18 against the torrent peer-wire and magnet plan, covering pure Swift core isolation, peer-wire framing, BEP 10/BEP 9 metadata exchange, storage writes, piece hash validation, resume-state persistence, partial deletion boundaries, UI state handling for `fetchingMetadata`, and deterministic mock tracker/peer fixtures.
- Added peer-wire frame length hardening so `TorrentPeerWireMessage.decodeFrame(...)`, `TorrentPeerWireSession.readFrame(...)`, and `TorrentMagnetMetadataSession.readFrame(...)` reject frames above `TorrentPeerWireMessage.maximumFrameLength` before reading large advertised payloads.
- Added regression tests for oversized peer-wire and extended metadata frames, including direct frame decoding and session-level pre-payload rejection.
- Hardened `TorrentContentStorage.write(...)` so an unexpected zero-byte `pwrite` result fails instead of spinning indefinitely.
- Confirmed `SwiftGetXTorrentCore` remains isolated from SwiftUI, SwiftData, AppKit, the C libtorrent target, and the app-level `LibtorrentAdapter` boundary.
- Confirmed tracker, peer-wire, storage, magnet, deletion, and adapter tests use local fixtures, mock transports, temporary directories, or loopback-style deterministic helpers rather than public tracker or swarm dependencies.

Verification evidence:

- `swift test --filter TorrentPeerWire` passed with 12 tests in 1 suite.
- `swift test --filter TorrentPeerWire --filter TorrentDownloadEngine --filter SwiftGetXTorrentCore` passed with 57 tests across 3 suites.
- `swift test` passed with 200 tests across 15 suites.
- `swift build` passed.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static core isolation audit with `rg -n "import (SwiftUI|SwiftData|AppKit)|CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore` found no matches.
- Static libtorrent boundary audit with `rg -n "CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore Sources/SwiftGetX/Services/TorrentDownloadEngine.swift Package.swift` found no matches in `Sources/SwiftGetXTorrentCore`; remaining references are limited to the optional `Package.swift` gate and `Sources/SwiftGetX/Services/TorrentDownloadEngine.swift` app adapter boundary.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; the linker emitted the existing local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 203 tests across 16 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- Real public torrent and magnet validation was not run in this check to keep verification deterministic and independent of external trackers or swarms.
- True seeding and upload behavior remain Task 20; the current Swift torrent path still completes downloads rather than proving long-lived seeding policy behavior.
- DHT, PEX, LSD, persisted node discovery, and source statistics remain Task 19, so trackerless peer discovery is not complete yet.
- Multi-peer concurrency is still MVP-level: richer duplicate endgame requests, peer rotation during slow magnet metadata exchange, long-lived peer statistics, and advanced retry policy remain future torrent hardening.
- Timeout-visible magnet behavior exposes pause/cancel paths, but richer UI actions such as copy magnet or continue waiting remain later UX/support-tooling work.

Next step:

- Task 19: DHT, PEX, and LSD.

## Task 19: DHT, PEX, and LSD

Status: [x]

Implement or clearly gate DHT KRPC/routing/bootstrap/get_peers/announce_peer, PEX, LSD, persisted DHT nodes, settings toggles, source statistics, and local mock tests for non-network behavior.

Work performed:

- Added pure Swift DHT support in `SwiftGetXTorrentCore`, including BEP 5 KRPC request/response encoding and parsing for `ping`, `find_node`, `get_peers`, and `announce_peer`.
- Added DHT routing-table and node persistence helpers so discovered nodes can be loaded from and saved to a task-specific JSON node store for faster subsequent startup.
- Added compact peer/node parsing and validation for DHT, plus deterministic PEX payload parsing and LSD search message formatting/parsing.
- Wired the Swift torrent adapter to combine tracker, DHT, PEX, and LSD peers, deduplicate by endpoint, respect max-connection limits, and expose per-source peer counts plus DHT node count in torrent health snapshots.
- Made the Swift adapter's DHT/PEX/LSD behavior obey runtime settings toggles, and force-disable those discovery paths for private torrents.
- Surfaced DHT node and peer-source statistics in the inspector health panel, with English and Simplified Chinese localization.
- Added local mock DHT/PEX/LSD tests for KRPC serialization, routing-table lookup, node-store persistence, DHT peer discovery, PEX parsing, LSD parsing, Swift adapter source statistics, settings toggles, and private-torrent gating.

Verification evidence:

- `swift test --filter DHT --filter PEX --filter LSD` passed with 1 selected adapter test.
- `swift test --filter SwiftGetXTorrentCore --filter TorrentDownloadEngine` passed with 53 tests across 2 suites, including DHT KRPC/routing/node-store, PEX/LSD parsing, adapter discovery source counts, settings toggles, and private torrent gating.
- `swift test` passed with 214 tests across 16 suites.
- `swift build` passed.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static core isolation audit with `rg -n "import (SwiftUI|SwiftData|AppKit)|CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore` found no matches.
- Static libtorrent boundary audit with `rg -n "CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore Sources/SwiftGetX/Services/TorrentDownloadEngine.swift Package.swift` found no matches in `Sources/SwiftGetXTorrentCore`; remaining references are limited to the optional `Package.swift` gate and `Sources/SwiftGetX/Services/TorrentDownloadEngine.swift` app adapter boundary.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; the linker emitted the existing local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 217 tests across 17 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- The automated tests use local mock DHT/KRPC, PEX, and LSD fixtures rather than public trackerless magnets or LAN multicast, keeping verification deterministic but leaving real-world NAT/firewall/bootstrap behavior for later manual validation.
- PEX and LSD are integrated through injectable discovery providers and protocol parsers; full long-running peer-session PEX extraction and live multicast listener behavior can be hardened further after seeding/upload and advanced peer runtime work.
- DHT routing is deliberately bounded and lightweight for the Swift MVP; richer bucket management, token policy, IPv6 compact forms, backoff persistence, and long-lived node health remain future hardening.

Next step:

- Task 20: Seeding State and Policies.

## Task 20: Seeding State and Policies

Status: [x]

Add `seeding` status, upload speed, share ratio, seeding time, per-task/global seeding policies, completion versus seeding-stop notifications, and stop-at-ratio/time/never-stop behavior.

Work performed:

- Added `TorrentSeedingLimitMode.stopAfterTime`, persisted `stopSeedingAfterSeconds` through `AppSettings`/`AppSettingsRecord`, and extended torrent runtime option JSON decoding with legacy-safe defaults.
- Added seeding duration to torrent connection and health diagnostics, plus UI display in task rows and inspector panels.
- Added global settings and per-task inspector controls for stop-at-ratio, stop-after-time, stop-when-complete, and never-stop seeding policy.
- Added `DownloadEngine.setTorrentRuntimeOptions(...)` and adapter plumbing so task-level policy edits reach active torrent engines.
- Updated the Swift torrent adapter to enter `.seeding` after data completion unless policy stops immediately, emit modeled upload rate/share ratio/seeding time snapshots, send tracker `completed` and later `stopped` announces, stop after ratio/time policy, and apply policy changes while already seeding.
- Updated the libtorrent adapter to preserve per-task runtime seeding options, track local seeding duration, pass ratio/time policy checks through `TorrentRuntimeOptions.shouldStopSeeding(...)`, and include seeding duration in connection/health snapshots.
- Updated coordinator notification behavior so first `.seeding` is treated as download-ready completion, while `.completed` after `.seeding` logs and notifies a distinct seeding-stop event.
- Added localization for seeding policy, seeding time, seeding-stop logs, and notifications.
- Added regression tests for seeding time JSON persistence, seeding policy forwarding, Swift adapter stop-after-time behavior, active seeding policy changes, tracker `stopped` announces, and stabilized magnet snapshot assertions around async callback ordering.

Verification evidence:

- `swift test --filter TorrentDownloadEngine` passed with 23 tests in 1 suite after the active policy update and snapshot assertion fix.
- `swift build` passed.
- `swift test` passed with 216 tests across 16 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; the linker emitted the existing local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 219 tests across 17 suites; the same local OpenSSL deployment-target linker warnings were present.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static core isolation audit with `rg -n "import (SwiftUI|SwiftData|AppKit)|CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore` found no matches.
- Static libtorrent boundary audit with `rg -n "CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore Sources/SwiftGetX/Services/TorrentDownloadEngine.swift Package.swift` found no matches in `Sources/SwiftGetXTorrentCore`; remaining references are limited to the optional `Package.swift` gate and app adapter boundary.

Remaining risk:

- The pure Swift adapter does not yet implement true peer-serving upload. It reports configured upload capacity and models uploaded bytes/share ratio for seeding-policy enforcement; real piece serving, uploaded-byte accounting from peer sessions, and richer long-lived seeding behavior remain future torrent runtime hardening.
- Stop-at-ratio in the Swift adapter can only auto-stop when a positive upload limit lets the model estimate uploaded bytes. With no modeled or real upload throughput, never-stop/manual stop remains the practical behavior.
- Seeding notifications and SwiftUI controls were compile/test verified and statically inspected, but not screenshot-tested or end-to-end exercised against a real public swarm.
- Optional libtorrent verification depends on the local prebuilt `.build/libtorrent/libtorrent-build/libtorrent-rasterbar.a` archive and Homebrew OpenSSL libraries; this task did not change the C wrapper or vendored native build.

Next step:

- Task 21: Torrent File Priority and Advanced UX.

## Task 21: Torrent File Priority and Advanced UX

Status: [x]

Support live file/folder priority, skip/low/normal/high, folder-level selection, extension filters, sequential download mode, recheck existing files, move/relocate downloads, and batch tracker operations.

Work performed:

- Added low torrent file priority while preserving existing stored raw values for skip/normal/high/max, plus explicit app-to-engine priority mapping for Swift and libtorrent paths.
- Updated live torrent file selection/priority handling so wanted low/normal/high/max files stay selected, skipped files are excluded, and Swift adapter piece selection/download totals are based on wanted content.
- Added Swift adapter recheck support that verifies existing wanted pieces against SHA-1 hashes, saves resume state, and reports wanted-byte totals plus tracker/discovery diagnostics.
- Added storage read support for torrent recheck verification across single-file and multi-file layouts.
- Added coordinator APIs for multi-file priority updates, folder priority updates, extension filters, batch tracker add/remove, relocation with exact known-content moves, and active-task pause/recheck after relocation.
- Updated libtorrent adapter live and startup file-priority paths to map app priorities to native 0...7 priorities and map native file snapshots back to app priorities.
- Added inspector controls for extension priority filters, folder-level priority menus, relocation path, sequential mode, and batch tracker add/remove/remove-listed/remove-all operations.
- Added English and Simplified Chinese localization for low priority, batch file/tracker logs, relocation logs, and new inspector controls.
- Added regression tests for priority persistence/mapping, coordinator folder/extension priority, batch trackers, relocation, Swift adapter skipped-file downloads, and recheck behavior.
- Committed Task 21 implementation as `83b1d23 Add advanced torrent file controls`.

Verification evidence:

- `swift test --filter DownloadCoordinator --filter TorrentDownloadEngine --filter TorrentFile` passed with 58 tests across 4 suites after rerunning with SwiftPM cache access.
- `swift build` passed.
- `swift test` passed with 223 tests across 16 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; linker emitted the existing local OpenSSL deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 226 tests across 17 suites; the same local OpenSSL deployment-target warnings were present.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static core isolation audit with `rg -n "import (SwiftUI|SwiftData|AppKit)|CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore` found no matches.
- Static libtorrent boundary audit with `rg -n "CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore Sources/SwiftGetX/Services/TorrentDownloadEngine.swift Package.swift` found no matches in `Sources/SwiftGetXTorrentCore`; remaining references are limited to the optional `Package.swift` gate and `Sources/SwiftGetX/Services/TorrentDownloadEngine.swift` app adapter boundary.

Remaining risk:

- Live Swift adapter priority changes are applied between piece downloads; an already in-flight piece is not cancelled mid-piece when a file is skipped.
- Folder controls group by torrent path prefixes and expose a bounded visible list in the inspector; very large torrent folder trees may need richer navigation in a later UX pass.
- Relocation moves only exact known content paths when the destination path does not already exist, then rechecks; complex partial-content conflicts remain conservative rather than interactive.
- Optional libtorrent verification still depends on the local prebuilt libtorrent archive and Homebrew OpenSSL libraries.

Next step:

- Large Check 7: Advanced Torrent UX.

## Large Check 7: Advanced Torrent UX

Status: [x]

Review Tasks 19-21 for correctness, feature gating, UI consistency, migration needs, and optional libtorrent parity.

Work performed:

- Audited Tasks 19-21 against the advanced torrent plan areas covering DHT/PEX/LSD source gating and statistics, seeding policy behavior, file priority controls, recheck/relocation, tracker operations, settings persistence, UI consistency, and optional libtorrent parity.
- Found that global DHT bootstrap node settings were persisted and editable but were not part of per-task `TorrentRuntimeOptions`, so the Swift adapter could still use its own hardcoded bootstrap list. Moved the default node list into `TorrentRuntimeOptions`, persisted runtime bootstrap nodes through `AppSettings`, included them in settings snapshot change detection, and made the Swift adapter parse and use runtime bootstrap nodes unless tests inject nodes directly.
- Found that duplicate single-tracker adds and missing single-tracker removes logged and forwarded no-op engine updates. Updated those operations to return without mutating, logging, or forwarding when no tracker actually changes.
- Found that torrent relocation paused active tasks and rechecked in separate asynchronous tasks, so recheck could race before pause. Sequenced active pause and recheck in one task.
- Added regression coverage for DHT bootstrap settings reaching Swift adapter discovery, DHT bootstrap persistence normalization, single-tracker no-op behavior, and the existing relocation/recheck path.

Verification evidence:

- `swift test --filter DownloadCoordinator --filter TorrentDownloadEngine --filter SwiftGetXTorrentCore --filter TorrentFile` passed with 92 tests across 5 suites after rerunning with SwiftPM cache access.
- `swift build` passed.
- `swift test` passed with 225 tests across 16 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static core isolation audit with `rg -n "import (SwiftUI|SwiftData|AppKit)|CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore` found no matches.
- Static libtorrent boundary audit with `rg -n "CSwiftGetXLibtorrent|LibtorrentAdapter" Sources/SwiftGetXTorrentCore Sources/SwiftGetX/Services/TorrentDownloadEngine.swift Package.swift` found no matches in `Sources/SwiftGetXTorrentCore`; remaining references are limited to the optional `Package.swift` gate and `Sources/SwiftGetX/Services/TorrentDownloadEngine.swift` app adapter boundary.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; linker emitted the existing local OpenSSL dylib deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 228 tests across 17 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- Real public swarm, trackerless magnet, and manual UI screenshot validation were not run; verification remained deterministic with local mocks, static inspection, builds, and tests.
- Live Swift priority changes still apply between pieces rather than cancelling an in-flight piece immediately.
- Relocation conflict handling remains conservative: it moves exact known content paths only when the destination does not already exist, then rechecks.
- Optional libtorrent verification depends on the local native archive and Homebrew OpenSSL libraries, and currently emits local deployment-target linker warnings.

Next step:

- Task 22: Batch Task Management and Categories.

## Task 22: Batch Task Management and Categories

Status: [x]

Add multi-select task UI and batch start/pause/delete/recheck/move/limit actions, cleanup completed/failed, categories/tags/smart filters, archive behavior, and clear local-file deletion confirmation.

Work performed:

- Added persistent task metadata for categories, normalized tags, archived state, and generic per-task download/upload speed limits.
- Added category inference for newly created HTTP, torrent, and preview-created tasks, including software/video/document/BT categories.
- Added coordinator-owned multi-selection state and batch APIs for resume/start, pause, cancel/retry, recheck, delete, queue moves, queue priority, category, tags, archive/unarchive, cleanup completed/failed/cancelled, and moving selected HTTP/torrent tasks.
- Extended filtering with smart filters for today, recent 7 days, large files, needs attention, and archived; normal filters now hide archived tasks unless the Archived filter is selected.
- Updated HTTP and torrent request plumbing so generic per-task speed limits reach HTTP worker throttling and torrent request limits, while preserving HTTP option fallback compatibility.
- Updated the task list, toolbar, content filtering, and sidebar for multi-select checkboxes, batch action bar, categories/tags sections, smart/archive filters, list cleanup/archive actions, and batch local-file deletion confirmation.
- Added English and Simplified Chinese localization for the new filters, categories, batch actions, logs, archive controls, and batch deletion messages.
- Added focused coordinator tests for category/tag/smart/archive filtering, inferred categories, batch selection operations, cleanup, per-task limits, and moving HTTP final/partial data.
- Committed Task 22 implementation as `a252fed Add batch task management`.

Verification evidence:

- `swift build` passed after rerunning with SwiftPM cache access.
- `swift test --filter DownloadCoordinator` passed with 30 tests in the `DownloadCoordinator` suite.
- `swift test` passed with 231 tests across 16 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; linker emitted the existing local OpenSSL deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 234 tests across 17 suites; the same local OpenSSL deployment-target linker warnings were present.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.

Remaining risk:

- Batch move UI currently exposes a conservative “move to default downloads folder” action rather than an interactive folder picker; the coordinator API supports explicit destination paths for tests and future UI.
- Category/tag assignment uses built-in category cases and simple preset tag actions in the task list; richer free-form tag editing can be improved in a later inspector/settings UX pass.
- SwiftUI behavior was build-verified and covered through coordinator tests, but not screenshot-tested in this session.
- Existing installed SwiftData stores were not migration-tested; new fields have default/optional values intended to keep existing records readable.

Next step:

- Task 23: Drag-and-Drop and System Integration.

## Task 23: Drag-and-Drop and System Integration

Status: [x]

Add drag-and-drop URL/text/torrent handling, Finder `.torrent` open-with plumbing where possible, Services/Share Extension plan or implementation, Dock progress/badge, and menu-bar progress refinements.

Work performed:

- Added `DownloadInputSourceCollector` to normalize URL/text/magnet/local `.torrent` inputs from drag/drop, Finder/Dock file-open events, and macOS Services pasteboards into public confirmation drafts.
- Added `DownloadDropSourceLoader` and a main-window SwiftUI drop target for URL, file URL, and plain-text drops, including a lightweight targeted overlay and reuse of the existing new-task confirmation/preview sheet.
- Routed unknown `.onOpenURL` inputs and `NSApplicationDelegate.application(_:open:)` file opens through the collector so local `.torrent` Finder Open With and Dock icon drops open the normal confirmation flow.
- Declared `.torrent` document support and `org.bittorrent.torrent` imported type in `AppInfo.plist` for packaged app bundles.
- Added an `NSServices` entry plus `AppDelegate` Services provider for selected text, URLs, file URLs, and Finder filenames, with localized failure text when no downloadable source is present.
- Added aggregate active progress, compact progress text, and Dock badge calculation to `MenuBarSnapshot`.
- Updated the menu-bar controller to show aggregate percent/speed in the status item, tooltip, and menu summary, and to render Dock tile progress plus badges for active, seeding, failed, and queued states.
- Added `Docs/SystemIntegrationPlan.md` documenting implemented local-system entry points and the remaining signed Share Extension path.
- Added focused tests for dropped/opened input collection, app bundle document/Services metadata, and Dock/menu aggregate progress behavior.
- Committed Task 23 implementation as `a182e86 Add system download integrations`.
- Committed verifier-driven local `.torrent` source normalization and plist-test fixes as `70f24d7 Normalize dropped torrent file sources`.

Verification evidence:

- `swift build` passed after rerunning with SwiftPM cache access.
- `swift test --filter DownloadInputSourceCollector --filter MenuBarSnapshot --filter AppResources` passed with 18 tests across 3 suites.
- `swift test` passed with 239 tests across 17 suites.
- `plutil -lint Sources/SwiftGetX/Resources/AppInfo.plist Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static diff review confirmed the Services/Share Extension boundary is documented and that the app-bundle `NSServices` entry, `.torrent` document type, and runtime handlers are present.

Remaining risk:

- Finder Open With and Services registration depend on a packaged/signed app bundle and Launch Services refresh; this task verified plist structure and runtime handlers, not an end-to-end Finder/Safari/TextEdit UI run.
- Dock tile progress is build-verified and backed by snapshot tests for its aggregate state, but the custom Dock drawing was not visually inspected in a running app.
- A full Share Extension remains planned because SwiftPM alone does not produce a signed macOS Share Extension target; `Docs/SystemIntegrationPlan.md` records the required Xcode/signing path.
- Drag-and-drop UI behavior was compile-verified and parser-tested, but not screenshot-tested.

Next step:

- Task 24: Inspector, Logs, Accessibility, and Localization.

## Task 24: Inspector, Logs, Accessibility, and Localization

Status: [x]

Add HTTP segment details, average/peak speed, start/finish/duration metadata, log clear/export/copy actions, direct error-card actions, VoiceOver labels, keyboard shortcuts, reduced-transparency handling, and hard-coded string cleanup.

Work performed:

- Added persisted transfer metrics to `DownloadTask`: start/finish timestamps, active duration, average speed, peak speed, and JSON-backed HTTP segment details.
- Extended HTTP snapshots to report single-stream and segmented transfer details, including segment ranges, downloaded bytes, speeds, and retry counts.
- Updated `DownloadCoordinator` to maintain timing metrics, persist segment snapshots, copy/export/clear logs, and finish terminal task timing consistently.
- Expanded the inspector with an HTTP Segments tab, average/peak speed and timing rows, direct error-card actions for copy/retry/reprobe, and log copy/export/clear controls.
- Added keyboard commands for selected-task start/pause, retry, verify, delete, and search focus.
- Added VoiceOver labels/help for toolbar controls, inspector log buttons, task-row icon controls, and tracker removal.
- Improved reduced-transparency fallbacks for drop overlay and task-row hover controls, building on the existing glass-surface fallbacks.
- Localized new inspector, metrics, log, command, HTTP segment, and torrent-detail strings in English and Simplified Chinese.
- Localized the libtorrent connection summary string.
- Added regression tests for coordinator metrics/log export/clear, HTTP segment snapshots, and per-segment progress tracking.
- Committed Task 24 implementation as `735f991 Add inspector metrics and log controls`.

Verification evidence:

- `swift build` passed.
- `swift test --filter DownloadCoordinator --filter SegmentPlan --filter HTTPDownloadEngine` passed with 77 tests across 3 suites.
- `swift test` passed with 242 tests across 17 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; linker emitted the existing local OpenSSL deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 245 tests across 18 suites; the same local OpenSSL deployment-target linker warnings were present.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static reduced-transparency audit confirmed remaining direct material fills in UI code are behind `accessibilityReduceTransparency` branches or existing reduced-transparency helper surfaces.

Remaining risk:

- SwiftUI inspector, keyboard, VoiceOver, and reduced-transparency behavior was compile/static verified and covered by model/engine/coordinator tests, but not screenshot-tested or manually exercised in a running app.
- Average speed is derived from persisted downloaded bytes over the recorded active interval and may differ from a moving-window speed display after long pauses or resumes.
- Log export writes beside the task save path by default; sandboxed packaged builds may still require future user-selected export destinations.
- Optional libtorrent verification depends on the local native archive and Homebrew OpenSSL libraries, which continue to emit deployment-target linker warnings.

Next step:

- Large Check 8: Main UI and Accessibility.

## Large Check 8: Main UI and Accessibility

Status: [x]

Review Tasks 22-24 for UX regressions, layout, localization, keyboard/VoiceOver coverage, data performance, and tests/build status.

Work performed:

- Audited Tasks 22-24 against `Docs/FunctionalImprovementOpportunities.md` sections 4.1-4.6 and 8.4, covering batch selection/actions, categories/tags/archive filters, drag/drop and system integration, Dock/menu-bar progress, inspector HTTP segment/log/error controls, keyboard paths, VoiceOver labels, reduced-transparency handling, localization cleanup, and large-list fetch behavior.
- Confirmed core batch/category/archive behavior is covered by coordinator tests, including multi-select pause/resume/recheck/archive/remove, cleanup completed/failed, category/tag/smart/archive filtering, per-task limits, HTTP data moves, and task lists beyond the old 500-task cap.
- Confirmed drag/drop/system integration is covered by input collector, app resource, and menu-bar snapshot tests, and by `Docs/SystemIntegrationPlan.md` documenting the remaining signed Share Extension boundary.
- Confirmed inspector segment/log metrics are covered by HTTP engine, segment progress, and coordinator snapshot/log-export tests.
- Found the selected-task keyboard command set lacked a Reveal-in-Finder path. Added `DownloadCoordinator.revealSelectedInFinder()`, wired `Command-Option-O`, and localized the new command label.
- Found remaining icon-only batch action bar controls and several inspector torrent file/tracker controls lacked explicit VoiceOver labels/help. Added accessibility labels/help for those controls.
- Found batch/context tag presets still used hard-coded English strings. Localized the preset tag labels in English and Simplified Chinese.
- Committed Large Check 8 fixes as `80055f8 Tighten main UI accessibility checks`.

Verification evidence:

- `swift build` passed after rerunning with SwiftPM cache access.
- Focused Large Check 8 tests passed: `swift test --filter DownloadCoordinator --filter DownloadInputSourceCollector --filter MenuBarSnapshot --filter AppResources --filter HTTPDownloadEngine --filter SegmentPlan` with 95 tests across 6 suites.
- `swift test` passed with 242 tests across 17 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; linker emitted the existing local OpenSSL deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 245 tests across 18 suites; the same local OpenSSL deployment-target linker warnings were present.
- `plutil -lint Sources/SwiftGetX/Resources/AppInfo.plist Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static hard-coded UI string scan found only intentional product/unit/acronym labels such as `SwiftGetX`, `BT`, and `1 MB/s`/`5 MB/s`/`10 MB/s` after localizing tag presets.

Remaining risk:

- SwiftUI layout, VoiceOver, keyboard, Dock tile drawing, drag/drop, and Services behavior were verified by compile/static inspection and model/resource tests, but not screenshot-tested or manually exercised in a packaged running app.
- Finder Open With, Dock file-open, and Services registration still depend on packaged app metadata and Launch Services refresh; `Docs/SystemIntegrationPlan.md` keeps the signed Share Extension path documented for later work.
- Main-window `@Query` still feeds the visible task list in memory; coordinator all-task fetches no longer use the old 500-task cap, but true paged/lazy task-list rendering remains later large-scale performance work.
- Optional libtorrent verification depends on the local native archive and Homebrew OpenSSL libraries, which continue to emit deployment-target linker warnings.

Next step:

- Task 25: Download Rules and System Behavior Settings.

## Task 25: Download Rules and System Behavior Settings

Status: [x]

Add rules for domain/extension/size save directories, thread counts, auto-start, browser takeover allow/deny lists, site headers/auth config, filename templates, login item, menu-bar background behavior, sleep prevention, exit prompts, and completion actions where local APIs permit.

Work performed:

- Added persisted `AppSettings`/`AppSettingsRecord` fields for download rules, browser takeover host allow/deny policy, login item, keep-running-in-menu-bar behavior, sleep prevention, active-task quit prompts, and completion actions.
- Added `DownloadRule` and `DownloadRuleTextFormat` for domain/extension/size matching, save directory overrides, filename templates, segment/retry overrides, auto-start control, and safe persistable site headers with sensitive headers filtered.
- Wired download rules into direct source creation and HTTP metadata-preview task creation, including rule-selected save paths, template-rendered filenames, HTTP option merging, and paused creation when `autoStart=false`.
- Added app-side browser takeover allow/deny enforcement for trusted native handoffs so blocked or non-allowed HTTP hosts are rejected back through the native ack path and Chrome can fall back safely.
- Added `SystemBehaviorController` for guarded launch-at-login registration, active-download sleep assertions, completion sound/Finder/open/script actions, plus coordinator/app integration for active-task sleep state and quit prompting.
- Added Settings UI sections for download rules, browser takeover host policy, system behavior toggles, and completion actions, with English and Simplified Chinese localization.
- Added regression tests for rule parsing/template rendering, sensitive header filtering, host policy boundaries, AppSettings persistence, coordinator rule application, and login-item bundle gating.
- Committed Task 25 implementation as `df38bf6 Add download rules and system behavior settings`.

Verification evidence:

- Initial focused test commands failed in the sandbox due SwiftPM/clang module cache write restrictions under `/Users/vancehudson/.cache/clang/ModuleCache`; reruns used approved SwiftPM cache access.
- `swift test --filter DownloadRule --filter DownloadCoordinator` passed with 36 tests across 2 suites after fixing test expectation typing.
- The first full `swift test` run caught a regression where HTTP preview auto-rename save paths renamed the displayed task. Fixed preview-created task naming so duplicate auto-rename keeps the original display name unless a rule explicitly changes it.
- `swift test --filter HTTPDownloadEngine --filter DownloadCoordinator --filter DownloadRule` passed with 76 tests across 3 suites after the preview-name fix.
- `swift build` passed.
- `swift test` passed with 248 tests across 19 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the local native libtorrent archive present; linker emitted the existing local OpenSSL deployment-target warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 251 tests across 20 suites; the same local OpenSSL deployment-target linker warnings were present.

Remaining risk:

- Launch-at-login, Finder reveal/open, completion sound/script execution, sleep assertions, and quit prompts are guarded or compile/test verified, but not end-to-end exercised in a packaged signed app during this session.
- Completion scripts only run when the configured path is executable and receive task metadata as arguments; richer script UI validation, sandbox entitlements, and audit logging remain future hardening.
- Browser takeover host policy is enforced in the app for trusted native handoffs, while extension-local takeover policy remains separately configured until later settings/import/export work unifies policy distribution.
- Sensitive rule headers are deliberately filtered from persisted rules; secure storage and richer site-auth configuration remain Task 26 scope.

Next step:

- Task 26: Persistence, Sensitive Data, and Large-Scale Performance.

## Task 26: Persistence, Sensitive Data, and Large-Scale Performance

Status: [x]

Add schema migration strategy for new fields, robust JSON recovery/cleanup, import/export, Keychain or runtime-only sensitive header storage, URL/log redaction, paged fetches/archiving, and menu-bar snapshot performance safeguards.

Work performed:

- Added a versioned SwiftData persistence helper and migration-plan boundary for the current `DownloadTask` and `AppSettingsRecord` schema, then switched app startup to use it.
- Added explicit settings schema version tracking plus startup repair for old settings records.
- Added robust persisted-data repair for malformed optional JSON fields on tasks and settings, plus sanitization for valid legacy JSON that still contained sensitive browser context, HTTP option headers, HTTP metadata URLs, or rule headers.
- Added `PrivacyRedactor` and wired log append/export, persisted error summaries, connection summaries, tracker errors, archive exports/imports, and URL query handling through redaction for token/auth/key/passkey/secret/session/signature-style values.
- Added a JSON import/export archive model for app settings and tasks, including archive version validation, sanitized task reconstruction, duplicate-skip import behavior, and replace-existing import cleanup of runtime-only sensitive state.
- Preserved runtime-only sensitive HTTP options for newly created HTTP tasks while keeping persisted options safe/redacted.
- Reworked menu-bar snapshots to use count/fetch-limit queries and direct task lookup instead of loading the full task table for menu refreshes.
- Added focused persistence/archive/redaction/menu performance tests, including versioned-container opening, legacy unversioned store reopening, invalid JSON repair, valid sensitive JSON cleanup, archive redaction/import, unsupported archive rejection, log redaction, and large menu-bar snapshot summarization.
- Committed Task 26 implementation as `3661cfc Add persistence archive and data repair`.

Verification evidence:

- Initial `swift test --filter PersistenceArchive` failed in the sandbox because SwiftPM could not write `/Users/vancehudson/.cache/clang/ModuleCache`; rerun used approved SwiftPM cache access.
- `swift test --filter PersistenceArchive` passed with 8 tests in 1 suite.
- `swift build` passed.
- `swift test` passed with 256 tests across 20 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 259 tests across 21 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- Static menu-bar performance search found no remaining `MenuBarController` paths that build snapshots from `coordinator?.allTasks()`.

Remaining risk:

- The import/export archive API is coordinator-level and covered by tests, but no dedicated Settings UI for manual archive selection was added in this task.
- Sensitive browser/per-task HTTP headers remain runtime-only and are deliberately not persisted to Keychain; authenticated downloads still need live browser context or re-entry after restart.
- Startup data repair currently fetches all tasks once to clean legacy JSON and text fields; this is acceptable for one-time cleanup but true paged repair/migration can be improved for very large existing libraries.
- The menu-bar snapshot avoids full-table loads for counts and recent items, but active aggregate progress still fetches active/progress tasks; very large simultaneous active sets may need aggregate SQL-style summaries later.
- Existing-store migration was covered with a local unversioned SwiftData store fixture, not a real user production store.

Next step:

- Task 27: Filesystem Safety and Protocol Expansion Boundaries.

## Task 27: Filesystem Safety and Protocol Expansion Boundaries

Status: [x]

Add disk-space/permission checks, safe deletion boundary checks, HTTP preallocation/capacity detection where possible, torrent sandbox/path checks, and document/test protocol expansion boundaries for FTP/SFTP, Metalink, HLS/DASH, multi-source, and GitHub/GitLab assets.

Work performed:

- Added `FileSystemSafety` for symlink-resolved boundary checks, safe local deletion filtering, destination directory/write/capacity preflight, torrent layout preflight, and best-effort macOS file preallocation.
- Routed HTTP final-file deletion, HTTP partial/temporary cleanup, coordinator task deletion, oversized segment repair, and torrent local-content deletion through bounded safe-deletion paths that refuse directory removal unless the path is exact known torrent content inside the save directory.
- Tightened HTTP partial data discovery so `.part`/manifest/segment sidecar directories are not treated as removable partial files.
- Extended HTTP capacity handling so segmented downloads account for merge scratch space when segmented mode is actually possible, and added best-effort preallocation for single-part and merge files without truncating progress-visible byte counts.
- Added Swift torrent runtime preflight for save directory permission/capacity and generated content path containment before peer/storage work starts.
- Added explicit containment invariants inside `TorrentContentLayout` so generated content roots and file URLs remain inside the selected save directory even before app-level runtime checks.
- Added `Docs/ProtocolExpansionBoundaries.md` documenting current app-native support and explicit deferred boundaries for FTP/SFTP, Metalink, HLS/DASH, mirror/multi-source downloads, and GitHub/GitLab release-asset API/auth integration.
- Added regression coverage for symlink deletion escapes, HTTP deletion refusing destination directories, torrent relocation/deletion boundaries, torrent layout containment, unsupported protocol parsing, HLS/DASH/Metalink-as-HTTP-manifest behavior, and GitHub/GitLab release assets remaining direct HTTP downloads.
- Committed Task 27 implementation as `1ab65ef Harden filesystem and protocol boundaries`.

Verification evidence:

- Initial sandboxed SwiftPM test command failed because SwiftPM could not write `/Users/vancehudson/.cache/clang/ModuleCache`; reruns used approved SwiftPM cache access.
- `swift test --filter FileManager --filter HTTPDownloadEngine --filter DownloadCoordinator --filter SourceParser --filter SwiftGetXTorrentCore` passed with 122 tests across 5 suites.
- `swift build` passed.
- `swift test` passed with 262 tests across 20 suites.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed; the existing local OpenSSL dylib deployment-target linker warnings were still present.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 265 tests across 21 suites; the existing local OpenSSL dylib deployment-target linker warnings were still present.

Remaining risk:

- macOS file preallocation is best-effort and intentionally ignored when the filesystem cannot reserve space; capacity checks still run before writes, but sparse files, APFS accounting, concurrent disk use, and network-mounted volumes can change available space after preflight.
- Torrent runtime preflight checks current save-directory permission and expected wanted bytes, but long-running downloads can still hit later filesystem changes such as permission revocation, disk pressure, or destination conflicts created after startup.
- FTP/SFTP, Metalink parsing, HLS/DASH media assembly, mirror/multi-source scheduling, and GitHub/GitLab release-asset API/auth integration are explicitly documented as unsupported boundaries rather than implemented engines.
- Optional libtorrent verification still depends on the local native archive and Homebrew OpenSSL libraries, which continue to emit deployment-target linker warnings in this environment.

Next step:

- Large Check 9: Settings, Persistence, and Filesystem Safety.

## Large Check 9: Settings, Persistence, and Filesystem Safety

Status: [x]

Review Tasks 25-27 for settings consistency, security, data migration, privacy, and large-library behavior. Run broad tests.

Work performed:

- Audited Tasks 25-27 against `Docs/FunctionalImprovementOpportunities.md` sections 5 and 6, covering settings/runtime consistency, download rules, browser takeover host policy, system behavior settings, schema/data repair, import/export redaction, large-library menu/system-policy behavior, and filesystem safety boundaries.
- Confirmed speed-limit persistence, download rules, browser takeover allow/deny policy, system behavior settings, robust JSON repair, archive import/export sanitation, menu-bar snapshot bounded queries, HTTP/torrent preflight, safe deletion, and protocol-boundary documentation are present and tested.
- Hardened `DownloadTask.browserContext` so direct assignment also persists only `BrowserDownloadContext.persistable`, preventing accidental Authorization/Cookie/header or handoff-source text persistence outside repair paths.
- Normalized torrent DHT bootstrap node settings when applying, creating, updating, or initializing `AppSettingsRecord`, so persisted settings do not keep whitespace/duplicate bootstrap entries that runtime options later collapse.
- Redacted engine snapshot `errorMessage` and connection-summary text before persistence/logging, including failed-task handling.
- Replaced the active-system-policy full task-table scan with a count query over active/seeding statuses, matching the menu-bar large-library safeguards.
- Fixed optional-libtorrent magnet preview tests to use valid magnet info hashes and assert runtime native-previewer availability rather than compile-time import alone.
- Stabilized one async torrent seeding test by waiting for completion status instead of a fixed snapshot count.
- Committed implementation/test fixes as `9dc1228 Tighten settings and persistence safety`.

Verification evidence:

- `swift test --filter DownloadCoordinator --filter PersistenceArchive --filter HTTPDownloadEngine --filter FileManager` passed with 90 tests across 4 suites after one test-expectation adjustment for URL-encoded redaction text.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test --filter TorrentDownloadEngine` passed with 27 tests in 1 suite after stabilizing the seeding-policy wait.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `git diff --check` passed.
- `swift build` passed.
- `swift test` passed with 265 tests across 20 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed; the existing local Homebrew OpenSSL dylib deployment-target linker warnings were still present.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 268 tests across 21 suites.

Remaining risk:

- Sensitive browser/per-task HTTP headers remain runtime-only by design, not Keychain-backed; authenticated restarts still require live browser context or re-entry.
- Startup data repair still performs a one-time full task fetch to clean legacy stores; this is acceptable for repair but true paged migration can be improved for very large existing libraries.
- Large-library safeguards now cover menu snapshots and active system-policy checks, but main-window SwiftUI `@Query` rendering is still not a fully paged virtualized task list.
- File preflight/deletion checks cannot prevent later external filesystem changes such as permission revocation, APFS capacity changes, network-volume behavior, or destination conflicts created after startup.
- Optional libtorrent verification still depends on the local native archive and Homebrew OpenSSL libraries, with existing deployment-target linker warnings during optional builds.

Next step:

- Task 28: Sparkle, Signing, Notarization, and Release Gates.

## Task 28: Sparkle, Signing, Notarization, and Release Gates

Status: [x]

Replace or enforce Sparkle public-key configuration, add release workflow checks for required secrets, signing/notarization verification commands, manual update status feedback, release notes wiring, and local-build-safe fallback behavior.

Work performed:

- Added `Scripts/validate-release.sh` with modes for Sparkle config, strict release environment secrets, app bundle signing checks, DMG signing/notary/staple checks, and appcast release-note/signature checks.
- Hardened `Scripts/package-dmg.sh` so local packaging still defaults to ad-hoc signing, while `SWIFTGETX_RELEASE_STRICT=1` requires Developer ID signing, hardened runtime, DMG signing, notarization, stapling, and release validation.
- Updated the tag release workflow to fail early on missing Apple/Sparkle/Chrome secrets, import the Developer ID certificate into a temporary keychain, package with strict signing/notary env, verify signed/notarized artifacts, and validate the Sparkle appcast before publishing it.
- Added a lightweight Sparkle config check to the normal build workflow without requiring Apple credentials for PR/main builds.
- Updated `Scripts/generate-appcast.sh` to wire `sparkle:releaseNotesLink`, include a description, normalize `v`-prefixed versions for GitHub release URLs, XML-escape release-note fields, and fail on empty EdDSA signatures.
- Added `ReleaseValidation` helpers and release validation tests for Sparkle public key shape, release workflow gates, package script strict/local behavior, appcast release notes, and build workflow local-safe validation.
- Changed `SoftwareUpdater` to use `SPUUpdaterDelegate` for manual update-check status feedback, including requested, update-found, up-to-date, and failed states, with redacted failure text.
- Surfaced manual update status text in the Updates settings tab and command help, with English and Simplified Chinese localization.
- Updated `Docs/sparkle-update-setup.md` to reflect the current non-placeholder Sparkle public key, required release secrets, strict release workflow, release notes, and local ad-hoc fallback behavior.
- Committed the implementation as `0764a26 Harden release update gates`.

Verification evidence:

- `bash -n Scripts/validate-release.sh` passed.
- `bash -n Scripts/package-dmg.sh` passed.
- `bash -n Scripts/generate-appcast.sh` passed.
- `plutil -lint Sources/SwiftGetX/Resources/AppInfo.plist Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings` passed.
- `Scripts/validate-release.sh sparkle` passed and confirmed the configured `SUPublicEDKey` is non-placeholder and decodes to a 32-byte Ed25519 public key.
- A temporary synthetic appcast passed `Scripts/validate-release.sh appcast <temp-appcast>`.
- `git diff --check` passed.
- `swift build` passed after rerunning with approved SwiftPM cache access.
- `swift test --filter ReleaseValidation --filter AppResources` passed with 15 tests across 2 suites.
- `swift test` passed with 273 tests across 21 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed with the existing local Homebrew OpenSSL deployment-target linker warnings.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 276 tests across 22 suites; the same existing OpenSSL deployment-target warnings appeared during linking.

Remaining risk:

- Actual Developer ID signing, Apple notarization, stapling, and Gatekeeper validation against Apple services were not exercised locally because the required Apple certificate and notary credentials are not present in this workspace.
- The GitHub release workflow was statically verified and covered by tests but was not run on GitHub in this session.
- The Sparkle public key is enforced as a valid non-placeholder Ed25519 public key, but the matching relationship between the committed public key and the GitHub `SPARKLE_EDDSA_PRIVATE_KEY` secret cannot be cryptographically proven here without access to the private secret.
- Strict release validation checks the app bundle and DMG artifacts, but real user Gatekeeper behavior still depends on Apple notarization acceptance for the exact release artifact produced by CI.
- Optional libtorrent verification still depends on the local native archive and Homebrew OpenSSL libraries, which continue to emit deployment-target linker warnings in this environment.

Next step:

- Task 29: Extension Distribution, Version Compatibility, and Licenses.

## Task 29: Extension Distribution, Version Compatibility, and Licenses

Status: [x]

Add extension/app/native-host version compatibility checks, Chrome extension release packaging path, installation guidance, fixed-ID strategy documentation, dependency/license acknowledgements, and optional libtorrent dependency cleanup guidance.

Work performed:

- Added shared browser integration compatibility metadata in `SwiftGetXCore`, including browser protocol version, native-host version, minimum extension version, minimum native-host version, and semver-style compatibility checks.
- Extended native messaging models, `SwiftGetXNativeHost`, the Chrome extension background/popup scripts, and app browser-setup deep-link handling so extension/native-host/app compatibility is checked before download handoff or extension pairing.
- Added visible extension/native-host incompatibility errors in the Chrome popup and app pairing rejection alerts, plus localized English and Simplified Chinese strings.
- Updated Chrome extension packaging to write `SwiftGetX-Chrome.release.json`, write the computed extension ID, require stable key plus expected ID in strict release mode, and fail before writing a CRX when the computed fixed ID does not match.
- Updated CI/release gates so release workflows require `CHROME_EXTENSION_ID`, run Chrome extension packaging in strict mode, upload release metadata, and no longer install Homebrew/CMake/Boost/OpenSSL for ordinary app packaging.
- Changed DMG packaging so optional libtorrent is built only when `SWIFTGETX_ENABLE_LIBTORRENT=1`, and bundled `Acknowledgements.md` into SwiftPM resources and packaged app resources.
- Added `Docs/ChromeExtensionDistribution.md`, `Docs/Acknowledgements.md`, packaged acknowledgement text, browser integration docs, release/Sparkle docs, README cleanup, and torrent docs clarifying fixed-ID distribution, Chrome Web Store path, compatibility matrix, license acknowledgements, and optional libtorrent dependency boundaries.
- Added tests for compatibility message fields, browser setup compatibility metadata parsing, release packaging/fixed-ID script behavior, workflow release metadata, bundled acknowledgements, and release/dependency documentation.
- Committed Task 29 implementation as `c4a9274 Add extension distribution compatibility gates`.

Verification evidence:

- `node --check Sources/SwiftGetX/Resources/ChromeExtension/background.js` passed.
- `node --check Sources/SwiftGetX/Resources/ChromeExtension/popup.js` passed.
- `node --check Scripts/make-crx.mjs` passed.
- `bash -n Scripts/package-chrome-extension.sh Scripts/package-dmg.sh Scripts/validate-release.sh Scripts/local-build.sh` passed.
- Chrome extension `manifest.json` plus English and Simplified Chinese locale JSON parsed successfully with Node.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings Sources/SwiftGetX/Resources/AppInfo.plist` passed.
- `Scripts/validate-release.sh sparkle` passed.
- `Scripts/package-chrome-extension.sh Sources/SwiftGetX/Resources/ChromeExtension /private/tmp/swiftgetx-chrome-test-2` passed and wrote ZIP, CRX, ID, and `SwiftGetX-Chrome.release.json`.
- Strict CRX mismatch smoke check with `SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` exited before writing the mismatched CRX.
- `swift test --filter NativeMessageHost --filter ReleaseValidation --filter AppResources` passed with 52 tests across 3 suites after rerunning with approved SwiftPM cache access.
- `swift build` passed.
- `swift test` passed with 278 tests across 21 suites.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` passed; the existing local Homebrew OpenSSL deployment-target linker warnings were still present.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` passed with 281 tests across 22 suites; the same existing OpenSSL deployment-target warnings appeared during linking.
- `git diff --check` passed.
- Static stale-wording audit found no remaining ordinary-release wording that described libtorrent/fallback as the default path in README/docs/package messaging.

Remaining risk:

- Real Chrome Web Store publication was not exercised because this workspace does not have Web Store credentials; the repository now documents the manual path and produces uploadable release ZIP/metadata artifacts.
- The fixed extension ID depends on the external `CHROME_EXTENSION_KEY_BASE64` and `CHROME_EXTENSION_ID` secrets matching in GitHub; local validation proves the scripts fail on mismatches, but cannot prove secret contents.
- End-to-end extension/native-host compatibility behavior was verified through JavaScript syntax/static checks, Swift message/deep-link tests, and packaging smoke tests, not through an installed Chrome profile automation run.
- Optional libtorrent verification still depends on the local native archive and Homebrew OpenSSL libraries, which continue to emit deployment-target linker warnings in this environment.

Next step:

- Task 30: Test, Diagnostics, and Support Tooling.

## Task 30: Test, Diagnostics, and Support Tooling

Status: [x]

Add browser E2E-friendly fixtures, torrent mock tracker/peer/DHT fixtures, network/file exception tests, UI/accessibility test coverage where feasible, diagnostic bundle export, redacted debug logs, crash-log guidance, extension popup native-message error details, and copy-diagnostics action.

Work performed:

- Added `DiagnosticLogLevel` with Normal/Verbose support and persisted it through `AppSettings`, `AppSettingsRecord`, `AppSettingsArchive`, Settings UI, and localization.
- Added `SupportDiagnosticsBuilder` with structured/text/JSON diagnostics bundles covering app/native-host/browser compatibility metadata, settings snapshots, native-host browser diagnostics, bounded task snapshots, recent redacted errors, and crash-log guidance.
- Added coordinator support actions for redacted diagnostics text, copy-to-pasteboard, JSON export, and verbose-only redacted debug log entries.
- Added Settings Browser Integration actions for Copy Diagnostics and Export Diagnostics, plus System settings for diagnostic log level.
- Extended the Chrome extension native-message error handling so popup diagnostics include structured details such as action, host name, runtime error, compatibility fields, rejected reason, and request ID, while preserving multiline display in the popup error panel.
- Added browser E2E-friendly Native Host scenario fixtures and torrent mock swarm fixtures under `Tests/SwiftGetXTests/Fixtures`, and copied test fixtures as SwiftPM test resources.
- Added `Docs/DiagnosticsAndSupport.md` documenting diagnostic bundle contents, redaction guarantees, verbose logging, extension error details, crash-log collection, and local fixture strategy.
- Added support diagnostics tests for redaction, normal-vs-verbose log handling, JSON stability, copy/export actions, settings/archive persistence, native-host snapshots, bundled fixture schemas, and extension popup error detail exposure.
- Added a local HTTP network exception regression where the test server drops the GET connection and the engine reports a failed network exception without writing a final file.

Verification evidence:

- `swift build` passed after rerunning with approved SwiftPM cache access.
- `swift test --filter SupportDiagnostics --filter HTTPDownloadEngine` passed with 47 tests across 2 suites.
- `swift test --filter SupportDiagnostics --filter AppResources` passed with 15 tests across 2 suites.
- `swift test` passed with 286 tests across 22 suites.
- `node --check Sources/SwiftGetX/Resources/ChromeExtension/background.js` passed.
- `node --check Sources/SwiftGetX/Resources/ChromeExtension/popup.js` passed.
- Node JSON parsing passed for the Chrome extension manifest/locales and the new browser/torrent fixture JSON files.
- `plutil -lint Sources/SwiftGetX/Resources/en.lproj/Localizable.strings Sources/SwiftGetX/Resources/zh-Hans.lproj/Localizable.strings Sources/SwiftGetX/Resources/AppInfo.plist` passed.
- `bash -n Scripts/package-dmg.sh Scripts/package-chrome-extension.sh Scripts/validate-release.sh Scripts/local-build.sh` passed.
- `git diff --check` passed.

Remaining risk:

- Browser E2E fixtures are bundled and schema-validated, but a real installed Chrome extension/native-host/browser profile automation run was not performed in this session.
- Diagnostic redaction covers URL tokens, sensitive headers, bearer tokens, and sensitive assignments, but support bundles can still include operationally sensitive file names, local paths, host names, and extension IDs; `Docs/DiagnosticsAndSupport.md` documents that users should review bundles before sharing.
- Verbose diagnostic logging is intentionally coordinator-gated and redacted, but only code paths that call `appendDebugLog` produce extra debug entries; deeper subsystem-specific debug instrumentation can be expanded as new support cases arise.
- The added network exception regression covers local connection interruption; broader real DNS/TLS/offline failures remain best covered by future external-environment or UI automation harnesses.

Next step:

- Large Check 10: Release and Quality.

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
