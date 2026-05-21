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
| `SPARKLE_EDDSA_PRIVATE_KEY` | Sparkle EdDSA 私钥，用于在 CI 中签名更新包 |
| `CHROME_EXTENSION_KEY_BASE64` | Chrome 扩展固定私钥，用于生成稳定 ID 的 CRX |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Developer ID Application 证书 `.p12` 的 base64 内容 |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | 上述 `.p12` 证书密码 |
| `APPLE_DEVELOPER_ID_APPLICATION_IDENTITY` | `codesign` 使用的 Developer ID Application 身份名称 |
| `APPLE_DEVELOPER_ID_DMG_IDENTITY` | 可选，DMG 签名身份；未设置时复用 Application 身份 |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API Key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect Issuer ID |
| `APPLE_NOTARY_KEY` 或 `APPLE_NOTARY_KEY_BASE64` | Notary API `.p8` 私钥明文或 base64 内容 |

`release.yml` 在运行测试和打包前会执行 `Scripts/validate-release.sh environment`。缺少以上必需 secret、Sparkle key 回退到占位值、或 feed URL 不合规时，release workflow 会明确失败。

## 3. 更新发布流程

当你推送一个新的版本 tag（如 `v1.1.0`）时，GitHub Actions 会自动：

1. 校验 release secrets 和 Sparkle 公钥/feed 配置
2. 编译项目并运行测试
3. 导入 Developer ID 证书到临时 keychain
4. 使用 hardened runtime 签名 App bundle、Native Host、Sparkle.framework 链路
5. 生成并签名 DMG，提交 `xcrun notarytool`，等待公证完成并 `stapler staple`
6. 使用 `codesign --verify`、`spctl --assess`、`xcrun stapler validate` 验证发布产物
7. 从 tag 中提取版本号（`v1.1.0` → `1.1.0`）
8. 使用 EdDSA 私钥签名 DMG
9. 生成 `appcast.xml`（包含版本号、下载地址、签名和 release notes 链接）
10. 将 `appcast.xml` 推送到 `gh-pages` 分支
11. 创建 GitHub Release 并上传 DMG/Chrome 扩展

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

> 本地默认产物适合开发和内部验证，但未公证。只有 `SWIFTGETX_RELEASE_STRICT=1` 路径生成的产物才应作为正式发布候选。

## 5. 故障排查

| 问题 | 解决方案 |
|---|---|
| "Check for Updates" 菜单项灰色不可用 | Sparkle 正在初始化，等待几秒后重试 |
| 更新检查报错 | 确认 `SUFeedURL` 地址可以正常访问 |
| 签名验证失败 | 确认 `SUPublicEDKey` 与 CI 中的 `SPARKLE_EDDSA_PRIVATE_KEY` 是同一对密钥 |
| CI 中 appcast 生成失败 | 确认已添加 `SPARKLE_EDDSA_PRIVATE_KEY` secret，且 `sign_update` 输出非空 EdDSA signature |
| Release workflow 一开始失败 | 运行日志会指出缺少哪个 secret；补齐 Developer ID、notary、Sparkle、Chrome 扩展签名 secret 后重试 |
| 公证或 Gatekeeper 校验失败 | 确认证书类型为 Developer ID Application、bundle 内嵌 framework/native host 已签名、DMG 已签名并完成 `stapler staple` |
