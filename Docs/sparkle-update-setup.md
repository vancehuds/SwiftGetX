# Sparkle 自动更新配置指南

SwiftGetX 使用 [Sparkle](https://sparkle-project.org) 框架提供应用内自动更新功能。本文档说明如何完成初始配置。

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

1. **公钥** → 复制到 `Sources/SwiftGetX/Resources/AppInfo.plist` 中 `SUPublicEDKey` 的值（替换 `REPLACE_WITH_YOUR_EDDSA_PUBLIC_KEY`）
2. **私钥** → 添加到 GitHub 仓库的 Secrets 中：
   - 前往仓库 Settings → Secrets and variables → Actions
   - 点击 "New repository secret"
   - Name: `SPARKLE_EDDSA_PRIVATE_KEY`
   - Value: 粘贴完整的私钥字符串

> ⚠️ **安全提示**: 私钥绝对不能提交到代码仓库中！只通过 GitHub Secrets 传递给 CI。

## 2. 配置说明

### Info.plist 中的 Sparkle 相关键

| 键 | 说明 | 当前值 |
|---|---|---|
| `SUFeedURL` | Appcast 订阅地址 | `https://raw.githubusercontent.com/vancehuds/SwiftGetX/gh-pages/appcast.xml` |
| `SUPublicEDKey` | EdDSA 公钥（用于验证更新签名） | 需替换为你的公钥 |
| `SUEnableAutomaticChecks` | 是否自动检查更新 | `true`（仅通知，不自动安装） |

### GitHub Actions Secrets

| Secret 名称 | 说明 |
|---|---|
| `SPARKLE_EDDSA_PRIVATE_KEY` | Sparkle EdDSA 私钥，用于在 CI 中签名更新包 |

## 3. 更新发布流程

当你推送一个新的版本 tag（如 `v1.1.0`）时，GitHub Actions 会自动：

1. 编译项目并打包 DMG
2. 从 tag 中提取版本号（`v1.1.0` → `1.1.0`）
3. 使用 EdDSA 私钥签名 DMG
4. 生成 `appcast.xml`（包含版本号、下载地址、签名）
5. 将 `appcast.xml` 推送到 `gh-pages` 分支
6. 创建 GitHub Release 并上传 DMG

### 用户端体验

- 应用启动时自动检查 `appcast.xml`
- 发现新版本时弹出 Sparkle 的更新通知对话框
- 用户可选择下载并安装更新
- 也可通过菜单栏 **SwiftGetX → 检查更新…** 手动检查

## 4. 本地测试

```bash
# 编译并运行应用
swift build
# 启动后在应用菜单中点击 "检查更新…"
# Sparkle 会尝试获取 appcast.xml 并检查是否有更新
```

> 首次运行时，由于尚未发布过 appcast，Sparkle 会提示"无可用更新"，这是正常的。

## 5. 故障排查

| 问题 | 解决方案 |
|---|---|
| "Check for Updates" 菜单项灰色不可用 | Sparkle 正在初始化，等待几秒后重试 |
| 更新检查报错 | 确认 `SUFeedURL` 地址可以正常访问 |
| 签名验证失败 | 确认 `SUPublicEDKey` 与 CI 中的 `SPARKLE_EDDSA_PRIVATE_KEY` 是同一对密钥 |
| CI 中 appcast 生成失败 | 确认已添加 `SPARKLE_EDDSA_PRIVATE_KEY` secret |
