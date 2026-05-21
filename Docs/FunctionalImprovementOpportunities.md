# SwiftGetX 功能完善建议清单

本文基于当前仓库源码、`README`、`Docs`、浏览器扩展、原生下载引擎、BT 适配层、设置页、菜单栏和测试用例梳理。目标不是重复已有功能，而是列出从“可用原型”走向“稳定日用下载管理器”还可以补齐的功能点。

## 当前功能基线

SwiftGetX 目前已经具备这些主干能力：

- macOS 14+ SwiftUI 三栏式下载管理界面，包含任务列表、检查器、设置页、菜单栏入口和剪贴板链接建议。
- HTTP/HTTPS 多线程分段下载，支持 Range 探测、断点续传、`.part` 临时文件、manifest、自动重试、全局限速、校验合并和重复文件重命名。
- Chrome/Chromium Manifest V3 扩展、Native Messaging host、`swiftgetx://download` 深度链接、Chrome/Atlas 扩展 ID 自动发现与 manifest 修复。
- BT/libtorrent 可插拔适配层，默认轻量 fallback，启用 `SWIFTGETX_ENABLE_LIBTORRENT=1` 后有真实 libtorrent wrapper、文件优先级、Tracker、Peer、健康信息和 resume data；如果改为自研 BT 引擎，现有 `TorrentEngineAdapter` 是最合适的迁移边界。
- Sparkle 更新框架接入、DMG/Chrome 扩展打包脚本、GitHub Actions 构建和 release workflow。

## 优先级总览

| 优先级 | 建议方向 | 原因 |
|---|---|---|
| P0 | 浏览器接管确认闭环 | 当前 Native Host 返回 `ok` 只代表成功打开 deep link，不代表主 App 已创建并持久化任务；Chrome 接管下载取消原生任务前缺少真实 App ack。 |
| P0 | 带认证/上下文的浏览器下载 | Native message 目前只有 URL/文件名/来源页，缺少 Cookie、Header、Referrer、POST/body 等上下文，真实站点下载容易失效。 |
| P0 | 自研 BT 引擎替代 libtorrent | 目标是避免外部库依赖，应把 libtorrent 从“发行依赖”降级为“过渡参考/测试 oracle”，并设计纯 Swift BT 协议栈。 |
| P0 | BT 路径语义与数据模型 | 当前 BT `savePath` 更像“任务路径”，但自研引擎需要明确保存目录、内容根目录、文件映射和删除边界。 |
| P0 | 签名、公证、Sparkle 密钥 | `SUPublicEDKey` 仍是占位值，发行版仍是 ad-hoc 签名，自动更新和 Gatekeeper 体验未闭环。 |
| P1 | 队列/批量任务管理 | 当前队列只有自动按并发数启动，缺少排序、优先级、批量选择、拖拽重排和自动恢复策略。 |
| P1 | HTTP 任务完整性与高级配置 | 需要 checksum、Content-Disposition 文件名、每任务限速/线程数/重试、代理、磁盘空间预检等日用能力。 |
| P1 | BT 日用体验与协议覆盖 | 需要 seeding 独立状态、按任务做种策略、启动后自动恢复、端口/加密、DHT、PEX、Tracker 批量管理。 |
| P1 | 首次启动和诊断引导 | Sidebar 当前静态显示浏览器已就绪，实际状态在设置页；需要把 native host、扩展、BT 引擎、更新配置做成首屏可见诊断。 |
| P2 | 更多浏览器与协议 | Safari 仍是资源模板，Firefox/Edge/Brave/Vivaldi/Arc 等未覆盖；FTP/SFTP、Metalink、HLS 等协议未支持。 |
| P2 | 可观测性、测试和安全加固 | 需要扩展端 E2E、自研 BT 协议 E2E、崩溃日志、隐私保护、深度链接安全和 torrent 路径穿越测试。 |

## 1. 浏览器接管与扩展集成

### 1.1 建立“主 App 已接收任务”的真实确认机制

当前 `SwiftGetXNativeHost` 收到 `download` 后调用 `NSWorkspace.shared.open(swiftgetx://download...)`，随后立即返回 `ok: true`。Chrome 扩展在收到 `ok` 后会 `cancel` 和 `erase` Chrome 原生下载。风险是：

- App 没启动成功、deep link 没被处理、SwiftData 保存失败、用户在确认弹窗里取消，Chrome 下载都可能已经被删除。
- 开启“接管下载后显示确认界面”时，`ok` 并不等于用户确认添加任务。

建议：

- 使用本地 XPC、Unix domain socket、localhost loopback HTTP 或 Distributed Notification 建立 App 与 native host 的同步 ack。
- Chrome 扩展只在 App 返回“任务已创建/用户确认”后取消 Chrome 原生下载。
- 如果用户取消 SwiftGetX 确认弹窗，扩展应让 Chrome 继续下载，或重新触发 Chrome 下载。
- Native host response 增加 `accepted`, `queued`, `requiresUserConfirmation`, `rejectedReason` 等字段。

### 1.2 传递认证下载上下文

当前 `BrowserDownloadMessage` 只有 `url`、`browser`、`suggestedFilename`、来源页标题/URL、`source`。很多实际下载依赖：

- Cookie / session。
- Authorization、Referer、User-Agent、Accept-Language 等 Header。
- `Content-Disposition` 文件名。
- POST 表单、CSRF token、临时签名 URL、一次性重定向。

建议：

- 扩展端对接 `chrome.cookies`、`webRequest` 或 `declarativeNetRequest` 可用能力，按用户授权传递最小必要 Header。
- App 端 `DownloadRequest` 扩展 `headers`、`method`、`body`、`referrer`、`userAgent`、`expiresAt`。
- 敏感 Header/Cookie 不进普通日志，必要时放 Keychain 或仅内存使用。
- 对 GitHub Actions artifacts 这类需要认证的下载，提供 GitHub token 或浏览器会话继承方案。

### 1.3 支持更多 Chromium 变体和浏览器

当前自动发现覆盖 Google Chrome 和 Atlas，Safari 是资源模板。

建议：

- 增加 Edge、Brave、Vivaldi、Arc、Chromium、Chrome Canary 的 profile 和 NativeMessagingHosts 目录。
- 设置页展示每个浏览器的安装状态、扩展 ID、manifest path、native host path。
- Safari 建立正式 App Extension target、签名、entitlements、打包到 `.app/Contents/PlugIns`。
- Firefox 支持可作为后续里程碑，Native Messaging manifest 目录和 manifest 字段不同，需要独立 registrar。

### 1.4 扩展下载扫描能力

当前页面扫描主要依赖常见文件扩展名和 `download` 属性。

建议：

- 扫描 `Content-Disposition` 可下载链接，需要 HEAD/轻量探测或后台 fetch。
- 识别视频/音频页面里的 HLS/DASH manifest、`.m3u8`、`.mpd`。
- 支持用户在 popup 中勾选部分候选链接，而不是只能发送全部。
- 候选列表超过 deep link 安全长度时，通过 native messaging 直接传 payload 或写临时 JSON 文件交给 App。
- 增加站点规则：排除图片小文件、排除广告 CDN、按文件类型过滤。

### 1.5 接管策略可配置

当前 Chrome 扩展默认开启接管，App 里只有“接管后显示确认界面”。

建议：

- 按文件类型、站点、文件大小、协议配置是否接管。
- 对小文件、网页保存、浏览器更新包等场景默认放行。
- 增加“按住 Option/Shift 时强制浏览器下载”或 context menu 里的临时规则。
- 接管失败时在扩展 popup 中显示可操作错误，而不是只打 badge。

### 1.6 Deep Link 安全与长度限制

`swiftgetx://download?url=...` 是公开 URL scheme，任何本机进程都可触发。

建议：

- 对外部 deep link 默认显示确认，尤其是多链接、file URL、本地 torrent 文件。
- 对 native host 交接使用带 nonce 的短期 token 或 App 内部 IPC，区分可信扩展来源和普通外部链接。
- 限制单次 URL 长度、任务数量和危险字符，避免超长 deep link 或日志污染。

## 2. HTTP/HTTPS 下载能力

### 2.1 解析服务器文件名和下载元数据

当前文件名主要来自 URL path 或浏览器建议文件名。

建议：

- 在 HEAD/GET 响应中解析 `Content-Disposition`，优先使用 `filename*` / `filename`。
- 保存 MIME type、服务器、最终 URL、重定向链、创建来源页。
- 新建任务确认页展示“最终文件名/大小/是否支持断点/来源域名”。

### 2.2 完整性校验

当前主要校验大小、ETag、Last-Modified 和 Range 一致性。

建议：

- 支持 SHA-256/SHA-1/MD5 校验值输入、从 `.sha256`/release metadata 自动发现。
- 支持 Metalink 或 checksum manifest。
- 下载完成后显示“已校验/未校验/校验失败”状态。
- 对失败校验提供重新下载损坏片段或整文件重试。

### 2.3 每任务级配置

当前线程数、重试次数、临时文件隐藏和限速主要是全局设置。

建议：

- 新建任务时可指定线程数、限速、重试次数、保存路径、文件名、Header。
- 任务运行时支持调整线程数和限速。
- 任务模型增加 `perTaskDownloadLimitBytes`、`segmentCountOverride`、`retryLimitOverride`。
- Toolbar 的限速菜单应同步写回 `AppSettings`，否则重启后会与设置页不一致。

### 2.4 队列调度增强

当前 `scheduleQueue()` 按创建时间和并发数启动 queued 任务。

建议：

- 支持拖拽排序、上移/下移、置顶、低优先级队列。
- 支持计划任务：稍后开始、仅 Wi-Fi、夜间下载、完成后睡眠/关机。
- 支持“失败自动回队列”与指数退避。
- 设置并发数变大后自动补充启动队列。
- App 重启后可配置“恢复为暂停”或“自动继续未完成任务”。
- 超过 500 个任务时避免 `DownloadCoordinator.allTasks()` 的 fetch limit 影响队列和菜单栏统计。

### 2.5 失败恢复与用户操作

建议增加：

- 单独的 `cancelled` 状态，不把用户取消混为 `failed`。
- “重试失败任务”“复制错误”“重新探测元数据”“重新命名并继续”。
- 对 401/403/404/416/429/5xx 给出面向用户的原因和下一步。
- 对磁盘空间不足、权限不足、路径不存在做启动前预检。
- 支持保留/删除/打开未完成 `.part` 文件的明确操作。

### 2.6 下载协议扩展

可选增强：

- FTP/SFTP。
- Metalink。
- HLS/DASH 视频下载。
- 镜像多源下载，同一文件多个 URL 并行拉取。
- GitHub/GitLab release assets 的 API 集成和认证。

## 3. BitTorrent 功能

### 3.1 确定 BT 引擎路线：自研优先，libtorrent 作为过渡

当前默认 SwiftPM 构建使用 `PlaceholderTorrentEngineAdapter`，只有 `SWIFTGETX_ENABLE_LIBTORRENT=1` 且本地静态库存在时才启用 native adapter。

建议：

- 将产品目标调整为“纯 Swift 自研 BT 引擎”，避免 release 产物依赖 libtorrent、Boost、OpenSSL。
- 保留 `TorrentEngineAdapter` 协议，新增 `SwiftTorrentEngineAdapter`，让 UI/SwiftData/Coordinator 不感知底层实现变化。
- 在自研引擎成熟前，libtorrent 仅作为开发期可选参考实现和行为对照，不作为默认发行依赖。
- App 内明确显示 BT 引擎类型：`SwiftTorrent`、`libtorrent fallback` 或 `unavailable`。
- CI 将重点从 `SWIFTGETX_ENABLE_LIBTORRENT=1` 迁移到纯 Swift BT 单元测试、协议模拟测试和本地集成测试。

### 3.2 明确 BT 保存路径语义

当前创建 BT 任务时 `savePath` 是 `saveDirectory.appendingPathComponent(preview.displayName)`，但 libtorrent 的 `save_path` 语义通常是保存目录。需要确认并统一：

- 单文件 torrent：UI 显示的是最终文件路径还是保存目录？
- 多文件 torrent：任务名目录和实际根目录是否重复嵌套？
- 删除任务时 `FileManager.removeItem(atPath: task.savePath)` 是否会误删目录或漏删实际内容？

建议：

- 模型拆分 `saveDirectory`、`outputName`、`finalFilePath`/`contentRootPath`。
- HTTP 和 BT 使用不同但清晰的路径展示。
- 删除本地文件前展示将删除的具体路径。

### 3.3 Seeding 独立状态与策略

当前 `DownloadStatus` 没有 `seeding`，BT 完成/做种混在 running/completed 逻辑里。

建议：

- 增加 `seeding` 状态，主列表显示上传速度、分享率、做种时间。
- 支持每任务 seeding 策略：完成即停、达到 ratio、达到做种时间、永不自动停止。
- 设置全局默认，任务可覆盖。
- 完成通知区分“下载完成”和“做种停止”。

### 3.4 Magnet 元数据体验

当前默认 fallback 下 magnet preview 会显示 native engine unavailable；native 下 preview 有超时。

建议：

- 允许“无需预览直接添加 magnet”，后台获取元数据后再弹出文件选择提醒。
- 获取元数据阶段显示 DHT 节点、Tracker 状态、已连接 peer 数。
- 对 metadata timeout 提供“继续等待”“直接添加”“复制 magnet”的操作。
- 支持解析 magnet 中的 `tr`、`dn`、`xl`，展示 tracker 列表。

### 3.5 Torrent 文件和路径安全

建议：

- 防止 torrent 内文件路径包含 `../`、绝对路径、隐藏控制字符或过长路径。
- UI 展示 torrent 文件树，而不只是平铺 path。
- 支持按文件夹勾选、按扩展名筛选、批量设置优先级。
- 对跨卷保存、权限错误、磁盘空间不足做预检。

### 3.6 BT 网络高级设置

建议补充：

- 监听端口配置、随机端口、UPnP/NAT-PMP 状态展示。
- 加密策略、uTP/TCP 开关。
- DHT bootstrap nodes 配置。
- 代理支持，尤其 SOCKS5。
- IP filter / blocklist。
- 最大活动 torrent 数、最大活动下载数、最大活动做种数。

### 3.7 Tracker 和 Peer 管理

当前检查器支持 add/remove tracker、force reannounce、peer 列表展示。

建议：

- 支持批量添加 tracker、按 tier 分组、编辑 tracker tier。
- 展示 scrape 结果、下一次 announce 倒计时、人类可读时间。
- Peer 支持复制地址、屏蔽 peer、显示国家/客户端统计。
- Tracker/Peer 面板加搜索和排序。

### 3.8 Resume 和重启恢复

当前 App 重启时 running/verifying 会被置为 paused。

建议：

- 对 BT 任务在启动时自动加载 resume data 并恢复 handle。
- 定时保存 resume data，而不只在 pause/remove/error/completion 时保存。
- 显示 resume data 最后保存时间和失败原因。
- 对移动后的文件支持重新定位和 recheck。

### 3.9 自研 BitTorrent 引擎详细计划

目标：实现一个不依赖 libtorrent/Boost/OpenSSL 的纯 Swift BT 下载引擎，优先满足 SwiftGetX 的桌面下载管理场景。可以使用 Apple 系统框架，例如 Foundation、Network.framework、CryptoKit、SystemConfiguration；不引入第三方协议库。

#### 3.9.1 总体原则

- 先支持 BitTorrent v1（BEP 3）和常见 magnet，再逐步扩展 DHT、PEX、加密、v2/hybrid torrent。
- 保持 `TorrentEngineAdapter` 作为唯一对上接口，新增引擎内部模块不直接依赖 SwiftUI 或 SwiftData。
- 协议实现和文件存储分层，便于用本地 mock peer/tracker 做确定性测试。
- 先做“少量 torrent 可稳定下载完成”，再做“大规模 swarm 性能优化”。
- 所有网络输入都按不可信处理：长度限制、路径规范化、piece 校验、peer message 校验必须从第一阶段就做。

#### 3.9.2 建议模块拆分

建议新增一个独立 target：

- `Sources/SwiftGetXTorrentCore`：纯 Swift BT 协议与存储核心，不依赖 SwiftUI/SwiftData。
- `Sources/SwiftGetX/Services/SwiftTorrentEngineAdapter.swift`：把核心引擎快照转换成现有 `DownloadSnapshot`。

核心模块建议：

- `Bencode`：bencode 编解码、canonical info dictionary bytes 保留、错误定位。
- `TorrentMetainfo`：`.torrent` 元数据、info hash v1、文件列表、piece length、piece hashes、announce/announce-list。
- `MagnetLink`：xt/dn/tr/xl/ws 解析，tracker 去重，display name 推断。
- `TrackerClient`：HTTP tracker announce/scrape、UDP tracker announce/scrape、tracker tier 调度和退避。
- `PeerWire`：TCP peer wire protocol、handshake、bitfield、interested/choke、request/piece/cancel、keepalive。
- `ExtensionProtocol`：BEP 10 extension handshake、BEP 9 metadata exchange，用于 magnet 获取元数据。
- `PieceManager`：piece/block 选择、稀有优先、顺序下载模式、优先级、跳过文件、校验队列。
- `TorrentStorage`：多文件映射、随机写入、稀疏文件、`.part`/resume state、路径安全、磁盘空间预检。
- `SwarmCoordinator`：peer 连接池、限速、并发 request pipeline、超时、重试、peer 评分。
- `SessionRuntime`：端口监听、任务生命周期、全局限速、后台恢复。
- `TorrentDiagnostics`：tracker/peer/health snapshot，供检查器展示。

#### 3.9.3 第一阶段：元数据与文件安全基础

交付目标：不联网也能完整解析 torrent，建立安全的本地文件映射和任务模型。

任务：

- 用纯 Swift 重写/强化当前 `TorrentFileParser`，保留 canonical `info` bytes，并计算 SHA-1 info hash。
- 解析 single-file、multi-file、announce-list、piece length、pieces hash 列表、private flag。
- Magnet parser 支持 `btih` hex/base32、`dn`、多个 `tr`、`xl`。
- 设计 `TorrentContentLayout`：保存目录、内容根目录、文件 path、offset、length、priority。
- 做路径安全：拒绝绝对路径、`..`、空组件、控制字符、超长路径、重复路径冲突。
- 设计自研 resume state schema：已完成 piece bitset、部分 block、文件修改校验、tracker 状态、peer ban list。

验收：

- 现有 `.torrent` parser tests 全部迁移到 `SwiftGetXTorrentCore`。
- 新增恶意路径、非法 bencode、超大字段、重复文件路径测试。
- 不依赖 libtorrent 即可在新建任务页展示 torrent 文件树、总大小、tracker 列表。

#### 3.9.4 第二阶段：HTTP/UDP Tracker 与任务调度

交付目标：能从 tracker 获取 peers，并在 UI 中显示 tracker 状态。

任务：

- HTTP tracker announce：`started`、普通 announce、`stopped`、`completed`。
- UDP tracker：connect request、announce request、transaction id 校验、超时重试。
- 支持 compact peer list 和非 compact peer list。
- Tracker tier 调度：同 tier 轮询、失败退避、成功 tracker 优先。
- 维护 announce interval、min interval、seed/leecher/downloaded 统计。
- 实现 scrape 可选路径，先不阻塞下载主流程。

验收：

- 本地 mock HTTP tracker 返回 peers，任务状态能从 `fetchingPeers` 进入 `connectingPeers`。
- UDP tracker 用本地 fixture 或轻量 mock server 测试 transaction id、超时、重试。
- 检查器能展示 tracker 状态、错误、下次 announce 时间。

#### 3.9.5 第三阶段：Peer Wire 最小下载闭环

交付目标：对一个本地受控 torrent，从 mock peer 下载完整单文件并通过 piece hash 校验。

任务：

- TCP 连接和 BitTorrent handshake：protocol string、reserved bytes、info hash、peer id。
- 基础消息：keepalive、choke、unchoke、interested、not interested、have、bitfield、request、piece、cancel。
- Block request pipeline：每 peer 多 outstanding requests，超时重发，最大 block size 限制。
- Piece 校验：所有 block 完成后 SHA-1 校验，失败则丢弃并降低 peer 分数。
- 基础 piece 选择：先 sequential，再 rarest-first。
- 写入 `TorrentStorage`，支持单文件和多文件跨边界写入。

验收：

- 本地 mock peer 完成单文件下载。
- 支持暂停、恢复、删除 partial data。
- piece hash 错误时不会写出完成状态。
- UI 能显示 downloaded、speed、ETA、peer count。

#### 3.9.6 第四阶段：真实 swarm MVP

交付目标：可下载公开、合法、健康的测试 torrent。

任务：

- 多 peer 连接池：最大连接数、每 torrent 连接数、连接超时、peer 去重。
- Rarest-first piece 选择、endgame mode。
- Peer 评分：超时、坏块、慢速、重复发送、协议错误。
- 全局和单任务下载/上传限速。
- 做种基础：响应其他 peer 的 interested/request，上传已完成 piece。
- 完成事件：向 tracker 发送 `completed`，进入 `seeding` 或按策略停止。

验收：

- 可下载至少 3 类公开测试 torrent：单文件、多文件、小 piece/大 piece。
- 断网/退出后能从 resume state 恢复。
- 与现有 `DownloadSnapshot` 字段对齐：文件列表、peer、tracker、health、runtime options。

#### 3.9.7 第五阶段：Magnet 元数据

交付目标：无需 `.torrent` 文件即可从 magnet 获取 metadata 并下载。

任务：

- BEP 10 extension handshake。
- BEP 9 `ut_metadata`：metadata_size、request/data/reject、分片重组。
- metadata 完成后校验 info hash，生成 `TorrentMetainfo`。
- Magnet 任务在 metadata 获取前显示 `fetchingMetadata`，获取后刷新文件列表。
- 支持 metadata timeout 后继续后台等待或用户手动取消。

验收：

- 本地 mock extended peer 可提供 metadata。
- 公开合法 magnet 能获取 metadata 并进入下载。
- 错误 metadata 必须被 info hash 校验拒绝。

#### 3.9.8 第六阶段：DHT、PEX、LSD

交付目标：减少对 tracker 的依赖，提升 magnet 可用性。

任务：

- DHT（BEP 5）：KRPC、routing table、bootstrap、get_peers、announce_peer。
- PEX（BEP 11）：从已连接 peer 获取更多 peers。
- LSD（BEP 14）：局域网发现，可作为低优先级。
- DHT node 持久化，启动后快速恢复。
- UI 展示 DHT nodes、PEX/LSD 开关和来源统计。

验收：

- 无 tracker 的合法 magnet 能通过 DHT 找到 peers。
- DHT 测试使用本地 KRPC mock，避免依赖外网。
- 设置页的 DHT/PEX/LSD 开关真实影响自研引擎。

#### 3.9.9 第七阶段：做种、优先级和高级体验

交付目标：补齐日用 BT 客户端体验。

任务：

- `seeding` 状态、分享率、上传速度、做种时间。
- 文件优先级实时生效：skip/low/normal/high。
- 文件夹级选择和扩展名筛选。
- 顺序下载模式。
- 重新校验已有文件。
- 移动下载位置和重新定位文件。
- Tracker 批量添加、删除、强制 announce。

验收：

- UI 现有文件/连接/健康面板无需大改即可展示自研引擎数据。
- 暂停/恢复/删除/重新检查与 HTTP 任务行为一致。
- 做种策略 stop when complete、stop at ratio、never stop 均可用。

#### 3.9.10 第八阶段：协议增强与兼容性

可放到稳定 MVP 之后：

- Peer encryption / protocol encryption。
- IPv6 peers。
- NAT-PMP/UPnP 端口映射。
- SOCKS5/HTTP proxy。
- Web seeds（BEP 19）。
- Private torrent 更严格的 DHT/PEX 禁用。
- BitTorrent v2 / hybrid torrent。
- Fast extension、holepunch 等增强协议。

#### 3.9.11 迁移和删库计划

- 第一步：保留现有 `LibtorrentAdapter`，新增 `SwiftTorrentEngineAdapter`，通过设置或编译 flag 切换。
- 第二步：自研引擎通过本地 mock 和公开测试 torrent 后，将默认 BT 引擎切到 `SwiftTorrentEngineAdapter`。
- 第三步：libtorrent target 只保留在开发分支或删除 `CSwiftGetXLibtorrent`、`Native/CSwiftGetXLibtorrent`、`Vendor/libtorrent`、相关脚本和文档。
- 第四步：更新 README/CI/release workflow，移除 Homebrew、Boost、OpenSSL、CMake 的普通构建要求。
- 第五步：保留一份兼容性报告，列出自研引擎支持/不支持的 BEP 和已知限制。

#### 3.9.12 风险与控制

- 协议复杂度高：先做可测试 MVP，不一开始追求完整 libtorrent 能力。
- 外网测试不稳定：所有核心行为优先用本地 mock tracker/peer/DHT 节点。
- 安全风险高：路径安全、长度限制、piece 校验、peer message 校验必须前置。
- 性能风险：Swift actor 和 FileHandle 写入需要压测，必要时引入专用 IO queue。
- 兼容性风险：用公开合法 torrent 做回归集合，记录失败样本和原因。

## 4. 任务管理与主界面体验

### 4.1 批量选择和批量操作

建议：

- 支持多选任务。
- 批量开始、暂停、删除、重新检查、移动文件、设置限速。
- 批量清理已完成/失败任务。
- 对批量删除本地文件提供明确确认。

### 4.2 队列和分类

建议：

- 任务分组/标签/分类，例如软件、视频、文档、BT。
- 按站点、文件类型、日期自动分类保存。
- 侧边栏增加智能筛选：今天、最近 7 天、大文件、需要处理、正在做种。
- 支持归档已完成任务，避免主列表无限增长。

### 4.3 拖拽和系统集成

建议：

- 支持拖拽 URL、文本、`.torrent` 文件到主窗口或 Dock 图标。
- 支持 Finder “打开方式”关联 `.torrent`。
- 支持 Services/Share Extension，从 Safari/Finder/其他 App 发送到 SwiftGetX。
- 支持 Dock 图标进度、Badge、菜单栏迷你进度。

### 4.4 新建任务确认页增强

建议：

- HTTP 任务也做元数据预览：文件名、大小、断点支持、最终 URL、响应类型。
- 多链接批量添加时支持逐项勾选、修改文件名和目录。
- 显示重复文件处理策略：自动重命名、覆盖、跳过、询问。
- 支持粘贴包含 Markdown、HTML、JSON 列表的链接并去重。

### 4.5 检查器增强

建议：

- HTTP 任务增加“分段详情”标签页：每段 range、大小、进度、速度、重试次数。
- Overview 中显示平均速度、峰值速度、开始时间、完成时间、耗时。
- Logs 支持清空、导出、复制全部。
- 错误卡片提供直接操作按钮。

### 4.6 可访问性和本地化

建议：

- 为图标按钮补充 VoiceOver label。
- 检查键盘导航和快捷键：新建、搜索、开始/暂停、删除、Reveal。
- 支持 Reduced Transparency，液态玻璃背景在降低透明度时改为实体背景。
- 清理硬编码英文字符串，例如 BT 连接摘要中的 `peers`、`ratio`、`seeds`、`tier`、`Native Host` 等。
- 菜单栏和扩展 popup 保持中英文术语一致。

## 5. 设置、偏好与策略

### 5.1 设置和运行时状态一致

当前设置页会持久化到 `AppSettingsRecord`，但 Toolbar 的限速菜单直接调用 `coordinator.setSpeedLimit`，不一定同步到 `AppSettings`。

建议：

- 所有限速入口统一写入 `AppSettings`。
- 设置页展示当前实际生效限速。
- 增加“临时限速”和“持久默认限速”的区分。

### 5.2 下载规则

建议：

- 按域名/扩展名/大小设置保存目录、线程数、是否自动开始。
- 浏览器接管 allowlist/denylist。
- 对特定站点自动附加 Header 或认证配置。
- 文件名模板，例如 `{date}/{domain}/{filename}`。

### 5.3 系统行为

建议：

- 登录时启动。
- 关闭窗口后保留菜单栏运行。
- 下载时防止系统睡眠。
- 退出时如果有任务运行，提示暂停/继续后台/确认退出。
- 下载完成后播放声音、通知、打开文件、执行脚本等后置动作。

## 6. 持久化、数据模型与安全

### 6.1 SwiftData schema 迁移

当前模型字段较多，后续新增 Header、分类、校验、路径拆分、seeding 状态时需要迁移策略。

建议：

- 定义 model version 和迁移计划。
- 对 JSON 字段解析失败提供恢复/清理路径。
- 增加导入/导出任务数据库和设置。

### 6.2 敏感信息保护

如果后续支持 Cookie、Header、token：

- 不在 `DownloadTask.source` 里保存含 token 的完整 URL，或至少做脱敏显示。
- Header/Cookie 存 Keychain 或仅作为短期运行态。
- 日志、通知、崩溃报告默认脱敏。

### 6.3 大规模任务性能

建议：

- 去掉或替换 `DownloadCoordinator.allTasks()` 的固定 500 fetch limit，改分页/归档。
- 主列表虚拟化和增量 fetch。
- 菜单栏只读取必要 snapshot，避免大量任务时频繁全量扫描。

### 6.4 文件系统安全

建议：

- 下载前检查目标目录权限和剩余空间。
- HTTP 合并时支持预分配或至少检测目标卷容量。
- 删除文件时防止路径越界和误删目录。
- 对 torrent 文件路径做规范化和沙盒边界检查。

## 7. 发布、更新与安装体验

### 7.1 签名和公证

当前 README 明确说明是未公证 ad-hoc 原型。

建议：

- 使用 Developer ID Application 签名。
- DMG 签名和 notarization。
- Native host、Sparkle.framework、扩展 bundle 全链路签名验证。
- 发布前自动检查 `codesign --verify`、`spctl --assess`、notary ticket。

### 7.2 Sparkle 更新闭环

当前 `AppInfo.plist` 的 `SUPublicEDKey` 是 `REPLACE_WITH_YOUR_EDDSA_PUBLIC_KEY`。

建议：

- 生成并填入 Sparkle public key。
- CI 中校验 secret 是否存在，缺失时 release workflow 明确失败。
- 更新弹窗显示 release notes。
- 增加手动检查更新入口的状态反馈。

### 7.3 Chrome 扩展发行

建议：

- 固定 CRX 私钥，保证 extension ID 稳定。
- 准备 Chrome Web Store 发行路径，降低用户手动加载 unpacked 扩展的门槛。
- App 内引导用户打开扩展安装页和 native host 诊断。
- 扩展版本与 App/native host 版本兼容检查。

### 7.4 依赖和许可证

建议：

- 如果仍暂时保留 libtorrent 参考实现，明确 libtorrent、Boost、OpenSSL、Sparkle 的许可证声明。
- 自研 BT 引擎成为默认路径后，Release 包普通运行依赖应只保留 Apple 系统框架和 Sparkle。
- Release 包内带 `Acknowledgements`。
- 删除 libtorrent 发行依赖后，清理 README、CI、脚本中 Homebrew/CMake/Boost/OpenSSL 的普通用户路径；如果保留开发期参考实现，则把这些要求标注为 optional。

## 8. 测试与质量保障

### 8.1 浏览器端 E2E

建议：

- 用 Chrome 自动化测试扩展 popup、context menu、download takeover、native host setup。
- 测试 native host 不可用、App 未启动、用户取消确认、App 保存失败时 Chrome 是否正确回退。
- 测试多 profile、多浏览器 manifest 修复。

### 8.2 自研 BT 测试

建议：

- CI 增加 `SwiftGetXTorrentCore` 单元测试和本地协议集成测试，不依赖外部 tracker 或公网 swarm。
- 使用受控 `.torrent` fixture、本地 HTTP/UDP tracker mock、本地 peer wire mock、DHT/KRPC mock。
- 测试 magnet metadata、file priority、resume state、piece hash 校验、seeding stop policy。
- 测试路径穿越、恶意 torrent metadata、异常 peer message、超长 bencode、坏 piece、重复/越界 block。
- 在自研引擎成熟前，可选保留 libtorrent 对照测试，但不作为 release 必要条件。

### 8.3 网络和文件异常测试

建议：

- 断网、DNS 失败、TLS 失败、服务器中断、Range 响应错误、ETag 改变。
- 磁盘满、无权限、目标被占用、文件被外部删除。
- 大文件、很多小文件、超多任务压力测试。

### 8.4 UI/可访问性测试

建议：

- SwiftUI snapshot 或 UI tests 覆盖主窗口、设置页、新建任务、检查器。
- 中英文、本地化缺失、长文件名、窄窗口布局。
- VoiceOver label 和键盘操作。

## 9. 可观测性和支持工具

建议增加：

- 诊断包导出：App 版本、native host 版本、扩展版本、manifest 状态、最近错误日志、脱敏任务信息。
- 可选崩溃报告或本地 crash log 指引。
- 下载任务 debug log 等级开关。
- 浏览器扩展 popup 中显示最近一次 native message 错误详情。
- App 内“复制诊断信息”按钮。

## 推荐路线图

### 第一阶段：接管可信和发行可信

1. 改造 native host/App ack，避免 Chrome 下载被过早取消。
2. 完成签名、公证、Sparkle key 和 release 验证。
3. App 内显示真实浏览器/native host/BT 引擎状态。
4. 建立 `SwiftGetXTorrentCore` target、BT 元数据解析测试和路径安全测试。

### 第二阶段：真实站点下载可用

1. 浏览器传递 Referrer/User-Agent/Cookie/Header 的最小实现。
2. HTTP 解析 Content-Disposition 并做元数据预览。
3. 增加每任务限速、线程数、重试和失败恢复操作。
4. 增加站点规则和浏览器接管 allowlist/denylist。

### 第三阶段：下载管理器体验补齐

1. 批量选择、队列重排、任务优先级。
2. 拖拽添加、`.torrent` 文件关联、Dock/菜单栏增强。
3. 自研 BT 最小下载闭环：tracker、peer wire、piece 校验、resume state。
4. 日志导出、诊断包和大规模任务归档。

### 第四阶段：自研 BT 完整化

1. Magnet metadata、DHT、PEX、LSD。
2. `seeding` 状态、做种策略、上传限速和分享率。
3. 文件夹级选择、顺序下载、重新校验、移动下载位置。
4. 将默认 BT 引擎切换为 `SwiftTorrentEngineAdapter`，libtorrent 降级为 optional reference 或删除。

### 第五阶段：生态扩展

1. Safari 正式扩展 target。
2. Edge/Brave/Vivaldi/Arc/Firefox 支持。
3. HLS/Metalink/镜像多源下载。
4. 更完整的代理、端口、加密、blocklist 等高级网络设置。

## 最值得优先处理的 10 个具体任务

1. 为 Chrome takeover 增加 App ack，用户取消确认时不取消 Chrome 原生下载。
2. 在设置页和侧边栏显示真实 Native Host/扩展状态，替换静态“浏览器已就绪”提示。
3. 填入 Sparkle public key 并完善 release workflow 的 secret 校验。
4. 建立 `SwiftGetXTorrentCore` target，先实现 bencode、metainfo、magnet parser 和 info hash。
5. 明确并修正 BT `savePath`/保存目录/删除本地文件语义，为自研存储层打基础。
6. HTTP 下载支持 `Content-Disposition` 文件名。
7. 新建 HTTP 任务前做 HEAD/Range 预览。
8. Toolbar 限速菜单与 `AppSettings` 持久化打通。
9. 增加批量选择和批量暂停/恢复/删除。
10. 增加自研 BT 的本地 mock tracker/peer 测试夹具。
