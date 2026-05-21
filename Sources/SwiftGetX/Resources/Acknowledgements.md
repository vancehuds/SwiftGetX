# SwiftGetX Acknowledgements

SwiftGetX is distributed under the license in the repository root `LICENSE` file.

Default release runtime dependencies:

- Apple system frameworks included with macOS.
- Sparkle 2.x for app update delivery and signature verification, licensed under the MIT License.

Optional development/reference dependencies:

- libtorrent 2.x is kept as an optional reference engine behind `SWIFTGETX_ENABLE_LIBTORRENT=1`; it is not required by the default SwiftTorrent release path. libtorrent is licensed under the BSD 3-Clause License.
- Boost headers used by the optional libtorrent build are licensed under the Boost Software License 1.0.
- OpenSSL 3.x from Homebrew may be used by the optional libtorrent build and is licensed under the Apache License 2.0.

The bundled Chrome extension and Native Messaging host use the same SwiftGetX repository license unless a file states otherwise.
