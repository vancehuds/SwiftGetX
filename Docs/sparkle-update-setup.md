# Sparkle 自动更新与发布配置指南

SwiftGetX 使用 [Sparkle](https://sparkle-project.org) 框架提供应用内自动更新功能。本文档说明如何维护 Sparkle 密钥、签名/公证发布包，以及本地构建的安全回退路径。

## 1. 生成 EdDSA 密钥对（一次性操作）

Sparkle 使用 EdDSA (Ed25519) 签名来验证更新包的完整性和真实性。你需要生成一个密钥对：

### 步骤

```bash
# 1. 先编译项目（SPM 会下载 Sparkle 包，其中包含命令行工具）
swift build

# 2. 找到 generate_keys 工具
find .build -name "generate_keys" -type f

# 3. 运行密钥生成工具
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

### 输出示例

工具会输出类似以下内容：

```
A network reachability query has begun
A network reachability query has been resolved
EdDSA (ed25519) pair:
private key (for signing updates):
bBhPh0hFAsHEKOFRy+...long base64 string...
public key (for including in your app):
dGhlIHB1YmxpYyBrZXkgZ29lcyBoZXJl
```

### 保存密钥

1. **公钥** → `Sources/SwiftGetX/Resources/AppInfo.plist` 中的 `SUPublicEDKey` 当前已配置为非占位 Ed25519 公钥。轮换密钥时，只替换为新的 32 字节 base64 公钥，不要提交私钥。
2. **私钥** → 添加到 GitHub 仓库的 Secrets 中：
   - 前往仓库 Settings → Secrets and variables → Actions
   - 点击 "New repository secret"
   - Name: `SPARKLE_EDDSA_PRIVATE_KEY`
   - Value: 粘贴完整的私钥字符串

> ⚠️ **安全提示**: 私钥绝对不能提交到代码仓库中！只通过 GitHub Secrets 传递给 CI。

发布校验会拒绝空值、`REPLACE_WITH_YOUR_EDDSA_PUBLIC_KEY` 等占位值，以及不能 base64 解码为 32 字节的 `SUPublicEDKey`。

## 2. 配置说明

### Info.plist 中的 Sparkle 相关键

| 键 | 说明 | 当前值 |
|---|---|---|
| `SUFeedURL` | Appcast 订阅地址 | `https://raw.githubusercontent.com/vancehuds/SwiftGetX/gh-pages/appcast.xml` |
| `SUPublicEDKey` | EdDSA 公钥（用于验证更新签名） | 已配置非占位公钥，发布前自动校验 |
| `SUEnableAutomaticChecks` | 是否自动检查更新 | `true`（仅通知，不自动安装） |

### GitHub Actions Secrets

| Secret 名称 | 说明 |
|---|---|
| `SPARKLE_EDDSA_PRIVATE_KEY` | 必需。Sparkle EdDSA 私钥，用于在 CI 中签名更新包 |
| `CHROME_EXTENSION_KEY_BASE64` | 可选。Chrome 扩展固定私钥，用于生成稳定 ID 的 CRX |
| `CHROME_EXTENSION_ID` | 可选。由固定私钥推导出的 Chrome 扩展固定 ID；提供时 CI 会校验 CRX ID 必须匹配 |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | 可选。Developer ID Application 证书 `.p12` 的 base64 内容；提供完整 Apple secrets 时启用签名/公证 strict 模式 |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | 可选。上述 `.p12` 证书密码 |
| `APPLE_DEVELOPER_ID_APPLICATION_IDENTITY` | 可选。`codesign` 使用的 Developer ID Application 身份名称 |
| `APPLE_DEVELOPER_ID_DMG_IDENTITY` | 可选，DMG 签名身份；未设置时复用 Application 身份 |
| `APPLE_NOTARY_KEY_ID` | 可选。App Store Connect API Key ID |
| `APPLE_NOTARY_ISSUER_ID` | 可选。App Store Connect Issuer ID |
| `APPLE_NOTARY_KEY` 或 `APPLE_NOTARY_KEY_BASE64` | 可选。Notary API `.p8` 私钥明文或 base64 内容 |

`release.yml` 会先检测 Apple signing/notary secrets。全部配置时启用 `SWIFTGETX_RELEASE_STRICT=1`，产物会进行 Developer ID 签名、公证和 stapling；完全未配置 Apple secrets 时会发布 ad-hoc signed app bundle 和未签名、未公证 DMG，适合没有付费 Apple Developer 账号的发布。只配置了一部分 Apple secrets 会明确失败，避免误把预期的正式签名发布降级成未签名发布。

`SPARKLE_EDDSA_PRIVATE_KEY` 仍然是 appcast 自动更新发布所需的 secret。Chrome 扩展固定 key/ID 可不配置；未配置时 CI 会生成临时 CRX key，扩展 ID 不保证跨版本稳定。

## 3. 更新发布流程

当你推送一个新的版本 tag（如 `v1.1.0`）时，GitHub Actions 会自动：

1. 检测 Apple signing mode 并校验 release 配置和 Sparkle 公钥/feed 配置
2. 编译项目并运行测试
3. 如果 Apple secrets 完整，导入 Developer ID 证书到临时 keychain；否则跳过
4. 打包 App bundle、Native Host、Sparkle.framework 链路
5. strict 模式下使用 hardened runtime 签名 DMG、提交 `xcrun notarytool` 并 `stapler staple`；unsigned 模式下生成 ad-hoc signed app 和未签名 DMG
6. 使用当前 release mode 对应的 `codesign`/DMG 校验验证发布产物
7. 从 tag 中提取版本号（`v1.1.0` → `1.1.0`）
8. 使用 EdDSA 私钥签名 DMG
9. 生成 `appcast.xml`（包含版本号、下载地址、签名和 release notes 链接）
10. 将 `appcast.xml` 推送到 `gh-pages` 分支
11. 创建 GitHub Release 并上传 DMG/Chrome 扩展以及扩展 release metadata

Chrome Web Store 上传路径和固定 ID 策略见 `Docs/ChromeExtensionDistribution.md`。当前 workflow 产出可上传到 Web Store 的 ZIP，但不自动调用 Web Store API，因为仓库不假设存在商店发布凭据。

### 用户端体验

- 应用启动时自动检查 `appcast.xml`
- 发现新版本时弹出 Sparkle 的更新通知对话框，并通过 appcast 中的 `sparkle:releaseNotesLink` 显示 GitHub Release notes
- 用户可选择下载并安装更新
- 也可通过菜单栏 **SwiftGetX → 检查更新…** 手动检查；设置页会显示手动检查已请求、无更新、发现更新或失败状态

## 4. 本地测试

```bash
# 本地 Sparkle 配置校验
Scripts/validate-release.sh sparkle

# 本地打包。默认使用 ad-hoc 签名，不需要 Apple 证书或 notary credentials。
Scripts/package-dmg.sh release dist --dmg

# 启用严格发布模式会强制 Developer ID 签名、公证、staple 和 Gatekeeper/DMG 校验。
SWIFTGETX_RELEASE_STRICT=1 \
SWIFTGETX_CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
APPLE_NOTARY_KEY_ID="..." \
APPLE_NOTARY_ISSUER_ID="..." \
APPLE_NOTARY_KEY_BASE64="..." \
Scripts/package-dmg.sh release dist --dmg
```

> 本地默认产物适合开发、内部验证，或没有付费 Apple Developer 账号时的公开发布，但未公证，用户首次打开时通常需要在系统设置里手动允许。`SWIFTGETX_RELEASE_STRICT=1` 路径用于生成可减少 Gatekeeper 警告的 Developer ID 签名/公证产物。

## 5. 故障排查

| 问题 | 解决方案 |
|---|---|
| "Check for Updates" 菜单项灰色不可用 | Sparkle 正在初始化，等待几秒后重试 |
| 更新检查报错 | 确认 `SUFeedURL` 地址可以正常访问 |
| 签名验证失败 | 确认 `SUPublicEDKey` 与 CI 中的 `SPARKLE_EDDSA_PRIVATE_KEY` 是同一对密钥 |
| CI 中 appcast 生成失败 | 确认已添加 `SPARKLE_EDDSA_PRIVATE_KEY` secret，且 `sign_update` 输出非空 EdDSA signature |
| Release workflow 一开始失败 | 运行日志会指出缺少哪个 secret；没有付费 Apple Developer 账号时请不要配置任何 Apple signing/notary secret，只保留 `SPARKLE_EDDSA_PRIVATE_KEY` |
| 公证或 Gatekeeper 校验失败 | 确认证书类型为 Developer ID Application、bundle 内嵌 framework/native host 已签名、DMG 已签名并完成 `stapler staple` |
