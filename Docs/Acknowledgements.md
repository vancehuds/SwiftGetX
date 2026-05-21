# Acknowledgements

This file is the source-readable acknowledgement summary for SwiftGetX releases. The packaged app also includes `Acknowledgements.md` in its resources.

## Default Release Runtime

- SwiftGetX: repository root license.
- Apple system frameworks: provided by macOS.
- Sparkle 2.x: MIT License.

## Optional Development / Reference Path

The default release path uses the pure Swift torrent engine and does not require libtorrent, Boost, OpenSSL, CMake, or Homebrew.

- libtorrent 2.x: BSD 3-Clause License. Kept as an optional reference engine behind `SWIFTGETX_ENABLE_LIBTORRENT=1`.
- Boost: Boost Software License 1.0. Used by the optional libtorrent build.
- OpenSSL 3.x: Apache License 2.0. Used by the optional libtorrent build when enabled.

Keep optional native dependency requirements documented only in development/reference sections unless the release path explicitly opts back into native libtorrent.
