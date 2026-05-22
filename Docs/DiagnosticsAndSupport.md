# Diagnostics and Support

SwiftGetX support diagnostics are designed to be useful without exposing browser session secrets or local authentication material.

## Diagnostic Bundle

The app can copy or export a redacted diagnostics report from Settings > Browser Integration. The report includes:

- SwiftGetX app version, Native Host version, browser protocol version, and compatibility minimums.
- Diagnostic log level.
- Selected settings such as queue limits, transfer limits, HTTP segment count, retry count, torrent engine, and language.
- Native Messaging status for supported Chromium-family browsers, including manifest path, Native Host path, extension IDs, and allowed-origin counts.
- A bounded snapshot of recent non-archived tasks, including kind, status, source, save path, byte counts, recent logs, error text, and connection summaries.
- Recent redacted task errors.
- Crash-log collection guidance.

The export path writes `SwiftGetX-Diagnostics.json` to the default download directory unless a caller supplies an explicit directory. Copy Diagnostics places the text form of the same bundle on the macOS pasteboard.

## Redaction Guarantees

Diagnostics, logs, archives, persisted task errors, tracker errors, and browser context snapshots pass through `PrivacyRedactor`. The redactor removes or masks:

- Sensitive URL query values such as `token`, `auth`, `signature`, `sig`, `key`, `passkey`, `secret`, and session-style values.
- Sensitive headers such as `Authorization`, `Cookie`, `Proxy-Authorization`, `X-API-Key`, auth tokens, and CSRF/XSRF tokens.
- Bearer tokens and simple sensitive key assignments in logs.

Sensitive browser and per-task HTTP headers remain runtime-only unless explicitly safe to persist. Diagnostic bundles should still be reviewed before sharing because file names, local paths, extension IDs, and host names can be operationally sensitive.

## Debug Log Level

Settings > System includes a Diagnostic Log Level picker:

- Normal records normal task lifecycle logs.
- Verbose allows additional support/debug entries through the coordinator debug-log path. These entries are still redacted before persistence or export.

Verbose logging is meant for short support sessions and should be returned to Normal after collecting diagnostics.

## Browser Extension Error Details

The Chrome extension popup shows the last native-message error. Details include the Native Messaging action, host name, runtime error, native host version, protocol version, compatibility fields, rejected reason, and request ID when available. URL payloads and request headers are intentionally omitted from the error detail object.

## Crash Logs

For crash reports:

- Open Console.app, search for `SwiftGetX`, and inspect the Crash Reports section.
- Or inspect `~/Library/Logs/DiagnosticReports` for files beginning with `SwiftGetX`.
- Attach the crash report together with the diagnostics bundle.

Do not include private download URLs, cookies, tokens, or account-specific pages in support notes unless they have been independently redacted.

## Local Test Fixtures

Task-quality tests avoid external services:

- Browser E2E-friendly scenarios live under `Tests/SwiftGetXTests/Fixtures/BrowserE2E`.
- Torrent mock swarm fixtures live under `Tests/SwiftGetXTests/Fixtures/Torrent`.
- HTTP/network/file exception tests use local servers, temporary directories, permission/capacity preflights, and deterministic mock behaviors.

These fixtures are intended for future Playwright/Chrome automation and current static/unit validation without depending on a public tracker, public swarm, or real browser profile.
