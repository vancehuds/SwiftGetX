# SwiftGetX System Integration Plan

This note records the Task 23 system-integration boundary for features that need app-bundle metadata, extension targets, or signing outside normal SwiftPM execution.

## Implemented in the macOS app

- Main-window drag and drop accepts URL drops, plain text containing URLs, magnet links, and local or remote `.torrent` sources. Valid sources open the normal new-task confirmation and preview flow.
- Finder and Dock file-open events route local `.torrent` files through the same confirmation flow.
- The packaged `AppInfo.plist` declares `.torrent` as an alternate document type with the `org.bittorrent.torrent` imported type, so packaged app bundles can appear in Finder Open With after Launch Services registration.
- The packaged `AppInfo.plist` declares an `NSServices` entry for selected text, URLs, file URLs, and Finder filenames. The app registers `AppDelegate` as the Services provider and routes accepted input through `DownloadInputSourceCollector`.
- The Dock tile shows active aggregate download progress and a compact badge. The menu-bar item reuses the same aggregate snapshot for percent, speed, tooltip, and menu summary.

## Share Extension Path

SwiftPM cannot produce a signed macOS Share Extension target by itself. The intended implementation path for a full Share Extension is:

1. Add an Xcode app project or generation script that wraps the existing SwiftPM targets and owns bundle signing.
2. Add a macOS Share Extension accepting `public.url`, `public.plain-text`, and `org.bittorrent.torrent`.
3. Have the extension validate and normalize inputs with the same rules as `DownloadInputSourceCollector`, then hand off through `swiftgetx://download` for small payloads or the native localhost payload path for large multi-link payloads.
4. Verify the signed app in Finder, Safari, and TextEdit with URL, selected text, and `.torrent` file inputs, then add screenshots or test notes to release validation.

Until that bundle/signing work exists, drag and drop, Finder Open With, Dock file open, and the app-bundle `NSServices` entry are the local-system entry points shipped from this repository.
