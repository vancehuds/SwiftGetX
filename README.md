<p align="center">
  <a href="https://github.com/vancehudson/SwiftGetX">
    <img src="Sources/SwiftGetX/Resources/Assets/AppIcon.png" alt="SwiftGetX Logo" width="128" height="128">
  </a>
</p>

<h1 align="center">SwiftGetX</h1>

<p align="center">
  <strong>macOS 原生轻量、高颜值的多线程与 BT 下载管理器</strong>
</p>

<p align="center">
  <a href="README.en.md">English</a> | <strong>简体中文</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-0066b2.svg?style=flat&logo=github" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-4ebd31.svg?style=flat&logo=apple" alt="Platform: macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-f05138.svg?style=flat&logo=swift" alt="Swift: 6.0">
  <img src="https://img.shields.io/badge/Xcode-15.0%2B-1572B6.svg?style=flat&logo=xcode" alt="Xcode: 15.0+">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/UI-SwiftUI-FF5A09.svg?style=flat&logo=swift" alt="UI: SwiftUI">
  <img src="https://img.shields.io/badge/Database-SwiftData-E34F26.svg?style=flat" alt="Database: SwiftData">
  <img src="https://img.shields.io/badge/Engine-HTTP%20%2F%20libtorrent-darkviolet.svg?style=flat" alt="Engine: HTTP / libtorrent">
  <img src="https://img.shields.io/badge/Extensions-Chrome%20%2F%20Safari-8A2BE2.svg?style=flat&logo=googlechrome" alt="Extensions: Chrome / Safari">
</p>


**SwiftGetX** 是一个面向 macOS 14+ 的轻量原生下载管理器原型，采用 **SwiftUI**、**SwiftData** 和 **Swift Package Manager** 构建。项目目标是在保持轻量原生体验的同时，提供 HTTP/HTTPS 下载、浏览器显式交接、剪贴板链接捕获，以及可选的 BT/libtorrent 下载能力。

---

## ✨ 核心特性

### 🎨 现代原生 UI
*   **液态玻璃设计**：采用符合 macOS 设计规范的三栏式交互界面，支持深色模式。
*   **交互细节**：包含任务列表、右侧属性检查器、工具栏、偏好设置窗口及常驻系统菜单栏（Menu Bar）图标。
*   **智能剪贴板**：自动检测剪贴板链接，并在主界面弹出流线型玻璃拟态的下载建议条。

### ⚡ 模块化 HTTP/HTTPS 下载引擎
*   **多线程分段**：支持高性能多线程多分段下载，支持 Range 断点续传。
*   **智能重试与限速**：具备元数据自动探测、自动重试、实时下载限速及重复文件覆盖保护。
*   **状态管理**：输出实时的多分段状态、聚合进度、预估完成时间（ETA）及平均下载速率。
*   **安全性**：使用临时 `.part` 文件存储未完成的下载，校验成功后无缝重命名。

### 🧩 零配置浏览器深度集成
*   **Chrome 下载接管**：内置 Chrome 扩展（Manifest V3），默认开启“下载接管”。当在 Chrome 中触发符合规则的下载任务时，扩展将任务透明接管，并通过 Native Messaging 协议派发给 SwiftGetX，随后自动取消 Chrome 原生下载任务。如果交接失败，Chrome 将无缝继续下载。
*   **自动发现与注册修复**：App 内置智能宿主扫描器，会在启动或激活时**自动发现**本地 Chrome/Chromium（如 Google Chrome 以及 OpenAI Atlas 浏览器）的 Extension 配置文件。自动检测 Extension ID 并修复或写入本地 Native Messaging 宿主 manifest 文件（`com.swiftgetx.native.json`），普通开发者或用户**无需手动配置 Extension ID** 即可直接通信。
*   **Safari 扩展占位**：提供 Safari Web Extension 资源模板，方便后续在 Xcode 中配置 App Extension Target 实施苹果签名链集成。
*   **深度链接支持**：注册了自定义协议 `swiftgetx://download?url=...` 与交互式发现协议 `swiftgetx://browser-setup`。

### 🧬 可插拔式 BitTorrent 引擎 (基于 libtorrent)
*   **隔离架构**：定义了高度抽象的 `TorrentEngineAdapter` 接口协议，将 BT 引擎的具体实现与主 App 彻底隔离。
*   **静态链接 wrapper**：仓库内置了 `arvidn/libtorrent` v2.0.12 的源码包，并通过 `CSwiftGetXLibtorrent` 提供 C/C++ 封装，通过 CMake 构建静态链接库绑定。
*   **灵活编译**：默认 SwiftPM 编译会使用轻量级占位适配器（零依赖，数秒内即可极速编译）。通过设置环境变量 `SWIFTGETX_ENABLE_LIBTORRENT=1` 即可动态无缝激活 Native 物理 BT 下载功能，支持 Magnet 磁力链接/种子文件解析、DHT/PEX 节点网络、Tracker 更新、多文件优先级选择等。

---

## 📐 项目架构与目录结构

SwiftGetX 的模块边界清晰、依赖单向：

```mermaid
graph TD
    classDef main fill:#E3F2FD,stroke:#1565C0,stroke-width:2px;
    classDef browser fill:#F1F8E9,stroke:#558B2F,stroke-width:2px;
    classDef core fill:#EDE7F6,stroke:#651FFF,stroke-width:2px;
    classDef engine fill:#FFF3E0,stroke:#FF8F00,stroke-width:2px;
    
    Chrome["Chrome/Atlas 浏览器扩展 (Manifest V3)"]:::browser
    NativeHost["SwiftGetXNativeHost (轻量 C 交接程序)"]:::browser
    MainApp["SwiftGetX 主程序 (SwiftUI 界面)"]:::main
    Models["SwiftData 数据持久化模型"]:::main
    Coordinator["Services & Coordinator 协调器"]:::main
    Adapter["DownloadEngineAdapter 统一接口"]:::core
    HTTPEngine["HTTPDownloadEngine 多线程引擎"]:::engine
    TorrentAdapter["TorrentEngineAdapter BT适配接口"]:::core
    LibtorrentWrapper["CSwiftGetXLibtorrent (C++ Wrapper)"]:::engine
    Libtorrent["arvidn/libtorrent 核心库"]:::engine

    Chrome <-->|"Native Messaging"| NativeHost
    NativeHost -->|"Deep Link (自定义协议派发)"| MainApp
    MainApp --> Models
    MainApp --> Coordinator
    Coordinator --> Adapter
    Adapter --> HTTPEngine
    Adapter --> TorrentAdapter
    TorrentAdapter -->|"SWIFTGETX_ENABLE_LIBTORRENT=1"| LibtorrentWrapper
    LibtorrentWrapper --> Libtorrent
```

### 📂 目录说明

*   `Sources/SwiftGetX/`：主 macOS 应用程序源码（UI、持久化服务、核心业务逻辑与 bundled 浏览器扩展资源）。
*   `Sources/SwiftGetXCore/`：共享协议模块。包含浏览器通讯协议、Deep Link 模型和 Native Messaging 的消息 Framing。
*   `Sources/SwiftGetXNativeHost/`：轻量级 C 语言浏览器交接进程，读取 Chrome Standard I/O 并派发 Deep Link。
*   `Sources/CSwiftGetXLibtorrent/`：C++ Bridge 封装。使得 Swift 可以直接通过 C-API 操纵 libtorrent。
*   `Native/CSwiftGetXLibtorrent/`：CMake 构建配置，用于自动化编译 libtorrent 静态库及其依赖。
*   `Vendor/libtorrent/`：采用 Git 子模块锁定的 upstream `arvidn/libtorrent` 源码。
*   `Tests/SwiftGetXTests/`：完整的单元和集成测试用例，内含本地分段 HTTP Mock Range 测试服务器。
*   `Scripts/`：辅助脚本（包括打包、安装 native-host 辅助脚本、libtorrent 编译脚本）。

---

## 📦 零门槛安装与使用教程 (开箱即用 - 从 Release 下载)

如果您不想本地编译代码，而是想直接从本仓库的 **Releases** 页面下载打包好的成品使用，请按照以下步骤操作：

### 第一步：安装主程序
1. 前往本仓库的 [Releases](https://github.com/vancehudson/SwiftGetX/releases) 页面下载最新版的 `SwiftGetX.dmg`。
2. 双击打开 `.dmg` 挂载卷，将 **SwiftGetX** 拖入您的 **Applications (应用程序)** 文件夹中。
3. **⚠️ 首次启动安全提示 (Gatekeeper 绕过)**：
   * 由于本应用是未公证的 Ad-hoc 签名开源原型，首次启动双击运行时，macOS 系统可能会拦截并提示：*“无法打开，因为 Apple 无法检查其是否包含恶意软件”* 或 *“来自未验证的开发者”*。
   * **解决方法**：请打开 macOS 的 **系统设置 -> 隐私与安全**，拉到页面最下方找到“安全性”一栏，点击 **“仍要打开” (Open Anyway)**，并输入您的 Mac 开机密码进行授权，之后即可正常启动应用。

### 第二步：安装并绑定 Chrome 浏览器扩展
1. 在 Releases 页面下载对应的 `SwiftGetX-Chrome.zip`。
2. 将该 `.zip` 压缩包解压到一个您**不会删除或移动**的固定目录（例如您的 `Documents` 或专门存放软件的目录）。
3. 打开 Chrome 浏览器，在地址栏输入 `chrome://extensions` 并回车。
4. 开启右上角的 **“开发者模式” (Developer Mode)** 开关。
5. 点击左上角的 **“加载已解压的扩展程序” (Load Unpacked)** 按钮，选择您刚刚解压出的文件夹目录加载扩展。
6. **激活自动绑定**：运行并激活一次 SwiftGetX 主程序。App 启动后会自动检测您本地已加载的 Chrome 扩展 ID，并自动在系统后台写入 Native Messaging 清单配置文件，完成完美对接！
7. **使用方法**：此时，在 Chrome 中右键点击任何可下载的链接或触发常规文件下载，扩展便会自动拦截，交接给 SwiftGetX 进行高性能多线程分段极速下载。

---

## 🛠️ 环境要求

*   **运行系统**：macOS 14 (Sonoma) 或更高版本。
*   **编译环境**：Swift 6.0 Toolchain / Xcode 15+。
*   **构建 BT 引擎依赖**（仅在启用 libtorrent 时需要）：
    ```sh
    brew install cmake boost openssl
    ```

---

## 🚀 快速上手 (Quick Start - 面向开发者本地编译)

### 一键本地编译与测试
仓库提供了本地开发入口脚本，默认执行轻量构建并运行测试（默认禁用 Native libtorrent，适合日常快速验证）：

```sh
Scripts/local-build.sh
```

常用参数：

```sh
# 只编译，不跑测试
Scripts/local-build.sh --skip-tests

# Release 构建
Scripts/local-build.sh --release

# 启用 Native libtorrent 后构建并测试
Scripts/local-build.sh --native-libtorrent

# 组装 SwiftGetX.app 与 SwiftGetX.dmg
Scripts/local-build.sh --release --dmg

# 构建后安装 Chrome Native Messaging Host（可省略 ID 自动发现）
Scripts/local-build.sh --install-native-host <your-extension-id>
```

### 1. 基础构建（极速开发模式 - 默认禁用 BT）
为了能让任何开发者在拿到仓库的 3 秒内成功编译并跑通，SwiftGetX 默认采用**占位适配器模式**，此时**完全不需要**下载复杂的 C++ 依赖：

```sh
# 1. 编译主 App 与 Native Host
swift build

# 2. 运行主应用程序
swift run SwiftGetX

# 3. 运行 Swift Testing 自动化测试
swift test
```

### 2. 进阶构建（激活 Native 物理 BT/磁力下载引擎）
要启用真实的物理 BT 引擎，需要编译内置的 `libtorrent` C++ 封装：

```sh
# 1. 自动拉取 libtorrent 依赖的子模块
git -C Vendor/libtorrent submodule update --init deps/try_signal deps/asio-gnutls

# 2. 编译 libtorrent 静态库 (使用 Boost & OpenSSL)
Scripts/build-libtorrent.sh

# 3. 设定环境变量开启 BT 适配器并编译
SWIFTGETX_ENABLE_LIBTORRENT=1 swift build

# 4. 运行 BT 功能测试
SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
```
> [!TIP]
> 如果你的 Homebrew 安装在自定义路径（如 Intel 芯片的 `/usr/local` ），请在编译前设定 `SWIFTGETX_HOMEBREW_PREFIX` 环境变量：
> `SWIFTGETX_HOMEBREW_PREFIX=/usr/local SWIFTGETX_ENABLE_LIBTORRENT=1 swift build`

---

## 🔌 浏览器交接与扩展集成

SwiftGetX 设计了一套精妙的**主动发现与自动自我修复机制**。

### Chrome / Chromium 浏览器设置
1.  **加载扩展**：打开 Chrome，访问 `chrome://extensions`，开启右上角的 **开发者模式**。点击 **加载已解压的扩展程序**，选择目录：
    `Sources/SwiftGetX/Resources/ChromeExtension`
2.  **自动绑定**：运行并激活一次 SwiftGetX 主 App。主 App 将会自动扫描你正在使用的 Chrome/Atlas 浏览器的 Extension 目录，识别到 SwiftGetX 扩展的本地 Extension ID 后，会自动在 `~/Library/Application Support/Google/Chrome/NativeMessagingHosts` 写入正确的清单配置文件。
3.  **开始接管**：在 Chrome 浏览器中随意右击一个下载链接，即可在右键菜单中看到 `使用 SwiftGetX 下载`；或者直接点击下载常规文件，扩展便会自动拦截，派送至 SwiftGetX 进行多线程极速下载！

> [!NOTE]
> **本地调试工具**：你也可以在开发期间手动注册 Native Host：
> ```sh
> Scripts/install-native-host.sh .build/arm64-apple-macosx/debug/SwiftGetXNativeHost <your-extension-id>
> ```

### Safari 浏览器集成
*   Safari 扩展资源位于 `Sources/SwiftGetX/Resources/SafariWebExtension`。
*   在正式发行版中，需由开发者在 Xcode 内将此目录配置为 Safari Extension Target，签名后打包嵌入主 `.app` 的 `Contents/PlugIns` 目录中。

---

## 📦 本地打包与 CI/CD

### 本地打包 Ad-hoc App
项目提供了一键打包和 Ad-hoc 签名脚本，方便直接打包出可脱离控制台运行的 `.app` 和 `.dmg`：

```sh
# 组装 SwiftGetX.app (Debug 版)
Scripts/package-dmg.sh debug dist

# 组装并打包出 SwiftGetX.dmg (Release 版，包含资源、图标并生成 Ad-hoc 签名)
Scripts/package-dmg.sh release dist --dmg
```

### GitHub Actions CI
项目在 `.github/workflows/` 下预置了全自动的流水线：
*   `build.yml`：每次触发 PR 或 Push 时自动在 `macos-15` 容器中编译、测试并生成可供下载的 DMG。
*   `release.yml`：当你向 GitHub 推送以 `v*` 开头的版本 Tag 时，自动编译、封包并自动创建 Release、上传安装 DMG 和 Chrome 扩展 ZIP/CRX 安装包。

---

## 🧪 自动化测试 (Testing)

测试是 SwiftGetX 品质的基石，我们使用 Swift 官方全新的 **Swift Testing** 框架构建测试组：

*   **测试覆盖范围**：深色模式适配器、链接捕获过滤、Native Messaging 报文封包/解包（Framing）、多段下载调度器（Segment Planner）、重复文件名冲突重命名算法，以及真实的本地分段 HTTP 断点续传正确性测试。
*   测试命令：`swift test` 或开启 BT 引擎测试 `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test`。

---

## ⚠️ 开源合规与发布安全注意事项

如果你准备打包发布或者向外界推广你的 SwiftGetX 衍生版本，请注意以下安全与规范要求：

1.  **沙盒与公证 (Sandboxing & Notarization)**：
    *   根据 macOS 的 Gatekeeper 机制，为避免出现“应用已损坏”的警告，发布包需要使用苹果开发者账号的 `Developer ID Application` 证书进行签名，并通过 `xcrun notarytool` 提交给苹果完成公证。
    *   由于 Native Messaging 机制需要启动辅助子进程 `SwiftGetXNativeHost`，如果 App 运行在严苛沙盒（App Sandbox）中，请确保辅助进程已注册并在宿主 App 的 App Group 内，或在非沙盒模式下发布。
2.  **不要将机密提交至仓库**：
    *   绝不要向 Git 提交本地调试生成的 `.pem` 密钥文件。
    *   不要提交任何苹果开发者的 `api_key` 配置文件或 Keychain 密码。

---

## 🤝 参与贡献

我们极其欢迎任何形式的贡献，无论是反馈 Bug、改进 UI，还是优化 libtorrent 的 Resume Data 机制！

1.  请确保代码保持 **4 空格缩进**，遵守 idiomatic Swift 风格。
2.  对所有状态、SwiftData 或持久层变更，标注 `@MainActor` 以防止并发数据隔离碰撞。
3.  提交 Pull Request 之前，务必确保 `swift test` 本地通过。

---

## 📄 开源许可证

本项目基于 [MIT 许可证](LICENSE) 开源。欢迎大家自由提取、改造或分发！

---
*版权所有 (c) 2026 Vance Hudson。感谢所有参与测试与使用本项目的开源社区成员。*
