# 安全与隐私（贡献者与发版前）

本文说明 **哪些数据不应进入 Git**、**应用内实际存放位置**，以及 **推送前如何自检**。与 `README.md` 中「隐私提示」互补：README 侧重用户侧能力说明，本文侧重仓库与密钥管理。

## 1. 仓库中不应出现的内容

以下内容一旦进入远程历史，即视为敏感信息泄露风险，应从提交中排除并在泄露后轮换密钥：

| 类型 | 示例 | 说明 |
|------|------|------|
| 大模型 API Key | `sk-…`、各云厂商控制台发放的密钥 | 仅通过应用内「连接」保存到 **钥匙串**，见 `KeychainStore` |
| Slack Bot Token | `xoxb-…` / `xoxp-…` 等 | 同上，钥匙串专用条目 |
| 个人访问令牌 | `ghp_…`、`github_pat_…` 等 | 若日后 CI 脚本需要，用 GitHub Actions **Secrets**，勿写进仓库 |
| 私有 Base URL 中带凭证 | `https://user:pass@host/…` | 配置里只应填无凭证的 API 基址；账号密码不属于本应用设计范围 |
| 本机绝对路径与账户名 | `/Users/yourname/...` | 易暴露身份；文档与脚本尽量用占位符或相对路径 |

**允许出现在仓库中的**（非密钥）：`PRODUCT_BUNDLE_IDENTIFIER`（如 `io.github.powerpan.DesktopPet`）、钥匙串 **Service 名字符串**（与 Keychain 条目类型对应，不是密钥本身）、文档中的公开 GitHub 仓库 URL。

**可选注意**：`DesktopPet.xcodeproj/project.pbxproj` 中的 **`DEVELOPMENT_TEAM`**（Apple 开发团队 ID）不是 API Key，但会标识签名所用团队；若仓库完全公开且你不希望暴露该 ID，可改为由每位贡献者在 Xcode 本地选择 Personal Team，或改用未纳入版本控制的 `*.xcconfig` 注入团队 ID（需在 README 中说明）。

## 2. 应用内数据落点（便于对照审计）

- **钥匙串**：当前服务商的 API Key、Slack Bot Token（`KeychainStore.swift`）。**不会**写入 `UserDefaults`。
- **UserDefaults**：模型名、Base URL、温度、触发器规则 JSON、对话与旁白历史（不含密钥）。截屏与键盘类能力受隐私总开关约束，见 README 与设置内文案。
- **运行时内存**：网络请求头中的 `Bearer` 等仅在内存中拼接，不应记录到日志文件（若新增日志，须避免打印完整 Key）。

## 3. 推送或发 PR 前的自检命令

在仓库根目录执行（检查已跟踪文件中的常见泄露形态）：

```bash
git grep -nE '(sk-[a-zA-Z0-9]{10,}|xox[baprs]-[a-zA-Z0-9-]{10,}|AIza[0-9A-Za-z_-]{20,}|ghp_[a-zA-Z0-9]{20,})' HEAD
```

无输出表示当前提交树中未匹配到上述**形态**（不能替代人工审查：自定义 token、JWT、内网密码等仍需留意）。

可选：检查是否误提交环境文件：

```bash
git ls-files | rg -i '\.(env|pem|p12|mobileprovision)$' || true
```

## 4. 若已误提交密钥

1. **立即**在对应服务商控制台 **作废/轮换** 该密钥（Git 历史中删除文件不能撤销已克隆的副本）。
2. 使用 `git filter-repo` 等工具从历史中清除敏感文件或行（需团队协调 force-push），或对新密钥换用新条目并假定旧密钥已暴露。

## 5. 相关源码入口

- `DesktopPet/Core/Agent/KeychainStore.swift`：钥匙串读写与通知名。
- `DesktopPet/Features/Overlay/AgentSettings/ConnectionTabView.swift`：UI 侧保存/清除密钥。
