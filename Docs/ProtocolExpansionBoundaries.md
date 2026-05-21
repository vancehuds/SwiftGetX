# Protocol Expansion Boundaries

SwiftGetX currently treats protocol support as engine-owned, not extension-owned. Browser scanning may surface links from many page contexts, but the app only creates native tasks for the engines below.

## App-Native Support

- HTTP and HTTPS direct downloads, including browser-provided headers while the handoff payload is alive.
- GitHub Actions artifact page URLs, normalized to the GitHub artifact ZIP API URL.
- Local `.torrent` files, remote `.torrent` URLs, and magnet links.

## Explicit Boundaries

- FTP and SFTP URLs are not extracted from generic text and do not have app-native transfer engines.
- Metalink URLs over HTTP/HTTPS are downloaded as manifest files only. SwiftGetX does not parse Metalink mirrors, checksums, or segmented source metadata yet.
- HLS/DASH manifest URLs such as `.m3u8` and `.mpd` are downloaded as ordinary HTTP files. Media playlist parsing, segment assembly, muxing, and DRM handling are out of scope for the current HTTP engine.
- Mirror or multi-source downloads are not scheduled as a single task. Multiple HTTP URLs remain separate downloads unless a future multi-source engine owns shared integrity and range coordination.
- GitHub and GitLab release asset URLs remain direct HTTP downloads. GitHub Actions artifact API normalization is the only repository-host API rewrite currently implemented; release-asset API auth and token management remain future work.

These boundaries are covered by parser tests so future protocol work has to add a real engine/parser path instead of silently reclassifying unsupported protocols.
