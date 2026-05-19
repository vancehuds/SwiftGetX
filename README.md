# SwiftGetX

SwiftGetX 是一个面向 macOS 14+ 的原生下载管理器原型，使用 SwiftUI、SwiftData 和 Swift Package Manager 构建。项目目标是在保持轻量原生体验的同时，提供 HTTP/HTTPS 下载、浏览器显式交接、剪贴板链接捕获，以及可选的 BT/libtorrent 下载能力。

> 当前仓库更接近可运行的工程原型，而不是已经完成签名、沙盒、Safari 扩展和 notarization 的发布包。生产发布仍需要 Apple Developer ID、Xcode app/extension target、最终 Chrome 扩展 ID，以及部署目标匹配的 OpenSSL/libtorrent 打包方案。

## 功能概览

- 原生 macOS SwiftUI 三栏界面，包含任务列表、详情检查器、工具栏、设置窗口和菜单栏入口。
- SwiftData 持久化下载任务、应用设置、BT 文件列表和文件选择状态。
- HTTP/HTTPS 下载引擎支持元数据探测、`.part` 临时文件、Range 断点续传、多分段下载、聚合进度、暂停/恢复、重试、限速和重复文件保护。
- 剪贴板链接检测，并在应用内显示液态玻璃风格的下载建议条。
- 统一 `DownloadCoordinator` 协调 HTTP 和 BT 下载生命周期。
- BT 下载通过 `TorrentEngineAdapter` 隔离实现，默认构建使用占位适配器；设置 `SWIFTGETX_ENABLE_LIBTORRENT=1` 后可启用 native libtorrent 适配器。
- Chrome Native Messaging 交接：浏览器扩展把下载请求发送给 `SwiftGetXNativeHost`，native host 再打开 `swiftgetx://download?...`。
- Safari 和 Chrome 扩展资源已放入 app resources，便于后续接入正式扩展 target。
- 单元和集成测试覆盖链接解析、Native Messaging framing、文件名冲突、分段计划、HTTP Range 下载和 BT 文件列表持久化。

## 项目结构

```text
Sources/
  SwiftGetX/                 主 macOS app：UI、服务、模型、资源
  SwiftGetXCore/             浏览器消息、deep link、Native Messaging 共享类型
  SwiftGetXNativeHost/       Chrome Native Messaging host 可执行文件
  CSwiftGetXLibtorrent/      可选 libtorrent C/C++ wrapper
Tests/SwiftGetXTests/        Swift Testing 测试
Docs/                        浏览器集成、BT 引擎和完成状态说明
Scripts/                     native host 安装、libtorrent 构建、app/DMG 打包脚本
Native/CSwiftGetXLibtorrent/ CMake 构建入口
Vendor/libtorrent/           vendored arvidn/libtorrent 源码
```

核心边界：

- UI 层在 `Sources/SwiftGetX/UI`。
- 下载编排和运行时服务在 `Sources/SwiftGetX/Services`。
- 持久化模型在 `Sources/SwiftGetX/Models`。
- 浏览器和 native host 共享协议在 `Sources/SwiftGetXCore`。
- 可选 BT native bridge 在 `Sources/CSwiftGetXLibtorrent` 和 `Native/CSwiftGetXLibtorrent`。

## 环境要求

- macOS 14 或更高版本。
- Swift 6 toolchain。
- Xcode Command Line Tools。
- 可选 BT native 构建需要 Homebrew、CMake、Boost 和 OpenSSL。

安装基础工具：

```sh
xcode-select --install
```

安装可选 BT native 依赖：

```sh
brew install cmake boost openssl
```

## 快速开始

构建：

```sh
swift build
```

运行开发版 app：

```sh
swift run SwiftGetX
```

运行测试：

```sh
swift test
```

默认 SwiftPM 构建不会链接 libtorrent，因此干净机器上也可以直接构建和测试。

## 可选：启用 libtorrent

仓库 vendored 了 `arvidn/libtorrent` v2.0.12，并通过 `CSwiftGetXLibtorrent` 提供 Swift 可调用的 native bridge。首次启用前需要初始化 libtorrent 依赖并构建静态库：

```sh
git -C Vendor/libtorrent submodule update --init deps/try_signal deps/asio-gnutls
Scripts/build-libtorrent.sh
```

启用 native adapter 后构建和测试：

```sh
SWIFTGETX_ENABLE_LIBTORRENT=1 swift build
SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
```

`Package.swift` 默认使用 `/opt/homebrew` 查找 OpenSSL 和 Boost。如果 Homebrew 安装在其他位置，可以设置：

```sh
SWIFTGETX_HOMEBREW_PREFIX=/path/to/homebrew SWIFTGETX_ENABLE_LIBTORRENT=1 swift build
```

当前 native BT 能力包括 magnet 和 `.torrent` 输入、DHT、PEX、tracker 更新、元数据获取、文件列表上报、文件选择优先级、recheck，以及上传/下载限速。仍待增强的生产能力包括 resume data 持久化、受控真实种子测试、做种比例策略和 release 签名打包。

## 浏览器集成

SwiftGetX 采用显式浏览器交接，不会静默拦截所有下载。

### Chrome

Chrome 扩展资源位于：

```text
Sources/SwiftGetX/Resources/ChromeExtension
```

构建 native host：

```sh
swift build
```

安装 Chrome Native Messaging host manifest：

```sh
Scripts/install-native-host.sh .build/arm64-apple-macosx/debug/SwiftGetXNativeHost <chrome-extension-id>
```

脚本会写入：

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.swiftgetx.native.json
```

Chrome 扩展调用 `chrome.runtime.sendNativeMessage("com.swiftgetx.native", ...)`，`SwiftGetXNativeHost` 读取 4-byte little-endian length-prefixed JSON 后打开 `swiftgetx://download?url=...`，主 app 通过 `onOpenURL` 接收。

### Safari

Safari Web Extension 资源位于：

```text
Sources/SwiftGetX/Resources/SafariWebExtension
```

当前仓库提供资源占位和交接逻辑说明。生产版本需要在 Xcode 中维护正式 app/extension target，并把扩展嵌入签名后的 macOS app bundle。

更多细节见 [Docs/BrowserIntegration.md](Docs/BrowserIntegration.md)。

## 打包与发布状态

`Scripts/package-dmg.sh` 可以从 SwiftPM 构建产物组装本地可运行的 `SwiftGetX.app`：

```sh
Scripts/package-dmg.sh debug dist
Scripts/package-dmg.sh release dist --dmg
```

脚本会把主 app、`SwiftGetXNativeHost`、SwiftPM 资源 bundle 和 app 图标复制进 bundle，并使用 ad-hoc 签名，便于本地查看和调试。正式发布仍需要：

1. 使用 Developer ID Application 证书签名。
2. 确认 Safari/Chrome 扩展 ID 和 Native Messaging manifest。
3. 使用 `xcrun notarytool` notarize，并用 `xcrun stapler` staple。

## 测试

常规测试：

```sh
swift test
```

启用 native BT 后的测试：

```sh
SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
```

测试使用 Swift Testing 的 `@Suite`、`@Test` 和 `#expect`。添加测试时优先使用临时目录和本地测试服务器，避免依赖外部网络。

## 常见问题

### `SWIFTGETX_ENABLE_LIBTORRENT=1` 构建失败

如果提示找不到 `.build/libtorrent/libtorrent-build/libtorrent-rasterbar.a`，先运行：

```sh
Scripts/build-libtorrent.sh
```

如果提示 libtorrent submodules 缺失，先运行：

```sh
git -C Vendor/libtorrent submodule update --init deps/try_signal deps/asio-gnutls
```

### OpenSSL 出现 macOS deployment target linker warning

Homebrew 的 OpenSSL bottle 可能会在 macOS 14 debug 构建时输出 deployment target 警告。当前 debug 构建可继续链接；生产打包应使用与部署目标匹配、可签名的 OpenSSL/libtorrent artifacts 或 vendored framework。

### Chrome 无法发送到 SwiftGetX

检查三件事：

- `SwiftGetXNativeHost` 已通过 `swift build` 构建。
- `Scripts/install-native-host.sh` 中传入的是实际 Chrome extension id。
- `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.swiftgetx.native.json` 里的 `path` 指向可执行的 native host。

## 贡献提示

- 保持现有边界：UI 放在 `UI`，编排和系统服务放在 `Services`，持久化模型放在 `Models`，共享消息代码放在 `SwiftGetXCore`。
- 使用 4 空格缩进和惯用 Swift 命名。
- 涉及 UI、SwiftData 或 observable 状态协调时使用 `@MainActor`。
- 提交前至少运行 `swift test`；如果改动 BT adapter 或 C wrapper，也运行 `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test`。
- 不要提交 `.build`、`DerivedData`、`dist`、签名身份、notarization profile、浏览器扩展私有 ID 或本地下载路径。

## 相关文档

- [Docs/BrowserIntegration.md](Docs/BrowserIntegration.md)
- [Docs/TorrentEngine.md](Docs/TorrentEngine.md)
- [Docs/PlanCompletion.md](Docs/PlanCompletion.md)
