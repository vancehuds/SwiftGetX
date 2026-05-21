# Chrome Extension Distribution

SwiftGetX ships the Chrome/Chromium extension as a release artifact and keeps Chrome Web Store publication as the preferred public distribution path when store credentials are available.

## Artifacts

`Scripts/package-chrome-extension.sh` creates:

- `SwiftGetX-Chrome.zip`: upload this ZIP to the Chrome Web Store or load it unpacked for development.
- `SwiftGetX-Chrome.crx`: a CRX signed with the configured extension key for internal validation.
- `SwiftGetX-Chrome.release.json`: release metadata with manifest version and computed extension ID.

Local packaging may use a temporary key. Strict release packaging requires a stable private key plus the expected fixed extension ID:

```sh
SWIFTGETX_RELEASE_STRICT=1 \
SWIFTGETX_CHROME_EXTENSION_KEY_BASE64="$CHROME_EXTENSION_KEY_BASE64" \
SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID="$CHROME_EXTENSION_ID" \
Scripts/package-chrome-extension.sh Sources/SwiftGetX/Resources/ChromeExtension dist/chrome
```

## Fixed ID Strategy

Chrome derives a CRX extension ID from the extension private key. SwiftGetX release builds must use the same private key for every release and verify the computed ID against `CHROME_EXTENSION_ID`.

Required release secrets:

- `CHROME_EXTENSION_KEY_BASE64`: base64-encoded PEM private key used to sign the CRX.
- `CHROME_EXTENSION_ID`: expected fixed extension ID derived from that key and used for release validation.

If the computed ID changes, packaging fails before artifacts are uploaded. This prevents accidentally publishing a CRX that cannot communicate with already paired native-host manifests.

## Chrome Web Store Path

1. Build the release extension ZIP with the strict command above.
2. Upload `SwiftGetX-Chrome.zip` to the Chrome Web Store developer dashboard.
3. Keep the Web Store listing's extension ID equal to `CHROME_EXTENSION_ID`.
4. Publish only after the matching SwiftGetX app/Native Host release is signed and notarized.
5. Use the app Settings Browser Integration row or the GitHub release page to guide users to the current extension install path.

Automated Web Store upload is not implemented because this repository does not assume store credentials are available in local development or CI.

## Compatibility Matrix

| Component | Current | Minimum peer |
|---|---:|---:|
| Browser native-message protocol | 1 | protocol 1 |
| Chrome extension | 0.2.0 | Native Host 0.2.0 |
| Native Host | 0.2.0 | Chrome extension 0.2.0 |

The extension sends `extensionVersion`, `minimumNativeHostVersion`, and `protocolVersion` with native messages and setup deep links. The native host responds with `version`, `protocolVersion`, `minimumExtensionVersion`, `minimumNativeHostVersion`, `compatible`, and optional `compatibilityMessage`. The app rejects incompatible setup deep links before pairing an extension ID.

## Installation Guidance

- Normal users should install the app from the latest release, then install the matching Chrome extension artifact or Web Store listing.
- The Settings Browser Integration row includes an extension install link plus native-host diagnostics and repair actions.
- Development users may load the unpacked extension from `Sources/SwiftGetX/Resources/ChromeExtension`, then run the extension popup's connection check to open the app pairing prompt.
