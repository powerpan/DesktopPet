# DesktopPet

基于 Swift + SwiftUI + AppKit 的 macOS 桌面宠物应用。运行后以**菜单栏图标**常驻，宠物使用**透明浮动面板**（`NSPanel` + `.floating`）显示在桌面上方；全局键盘与 `⌘K` 显隐依赖**辅助功能**授权。

## 环境要求

- macOS 14.0+
- Xcode（建议最新稳定版）
- Swift 5+
- 完整 Xcode（非仅 Command Line Tools）

## 快速开始

1. 克隆仓库

   ```bash
   git clone https://github.com/powerpan/DesktopPet.git
   cd DesktopPet
   ```

2. 用 Xcode 打开 `DesktopPet.xcodeproj`，选择 **My Mac**，按 **⌘R** 运行。
3. 在菜单栏点击 **爪印图标**，使用「辅助功能与权限说明」或首次弹窗完成 **辅助功能** 授权。（若你直接打开系统设置、列表里还没有 DesktopPet：请先回到本应用，点权限窗口里的 **「打开系统设置」** 或 **「让我在列表中出现」**，系统需要先登记本应用才会出现在该列表。）
4. 系统设置中也可搜索「辅助功能」，勾选 **DesktopPet**。当前工程的 **Bundle ID** 为 `io.github.powerpan.DesktopPet`（若你曾用过 `com.example.DesktopPet` 的旧构建，请在辅助功能列表里用「−」删掉所有旧项，再退出应用并从 Xcode 重新 Run，只勾选**当前 DerivedData 路径**对应的一条）。
5. 若勾选后仍显示未信任：菜单栏退出应用 → Xcode 再 Run → 在权限窗口点 **重新检测**；仍不行时在终端执行 `tccutil reset Accessibility io.github.powerpan.DesktopPet`，然后重新勾选。从「系统设置」切回本应用后，应用会在数秒内自动再检测几次以应对系统延迟。
6. **若列表已勾选但应用内仍显示未信任（`AXIsProcessTrusted` 一直为 false）**：先在 Xcode 的 **Signing & Capabilities** 里为 **DesktopPet** 目标选择 **Team**（免费 **Personal Team** 即可），**不要**留空 Team 只靠「Sign to Run Locally」。然后 **Product → Clean Build Folder**，再 Run；在辅助功能里删掉所有旧 **DesktopPet** 后只勾选当前路径。可用终端自检签名是否带团队：`codesign -dvvv /你的/DesktopPet.app 路径 2>&1 | grep -E 'Authority|TeamIdentifier|adhoc'`（无 `TeamIdentifier` 时优先修签名再谈权限）。

## 使用说明

- **菜单栏**：点击爪印图标可显示/隐藏宠物、**显示/隐藏饲养面板**、**显示/隐藏对话面板**、打开**智能体设置**（多套服务商的 Base URL / 模型 / **钥匙串分账户** API Key、触发器与隐私开关）、打开权限说明、进入系统「设置…」面板（`⌘,`）、退出应用。
- **桌镜卡片**：标题为 **「七七猫1.0」**；底部保留 **英文** 状态枚举名（如 `idle`、`keyTap`）；键入历史为单行摘要，与桌镜图叠层分离布局。
- **⌘K**：全局快捷键，切换宠物窗口显示（需已授予辅助功能）。
- **鼠标穿透**：菜单栏 **设置…** 与窗口右上角按钮共用同一开关。开启时精灵区不参与命中；`PetRootContainerView` 包络外 `hitTest` 为 `nil`，包络内只转发 `NSHostingView.hitTest`（**不用** `?? hostingView`）。`PetSpriteView` 使用与圆角一致的 `contentShape`。宠物根视图**不再**整卡 `.padding(8)`，窗口边长由 `PetConfig.exteriorHitSide` 取「视觉边长 + 约 6pt」以尽量消掉隐形外圈。穿透关闭时拖窗请点在**材质卡片**上。
- **缩放**：滑条 **0.6～1.2**（最大整窗约等于此前仅拉到 1.2× 时的体量，不再支持 1.8）。卡片画布基准 **176pt**（`PetConfig.petCanvasLayoutPoints`，小于原 220）以减小占位。`visualBaselineFactor`（0.6）仍使 **1.0 档** 视觉约等于更早一版「相对 0.6」的体量。连续拖动滑条时窗口以**本轮第一次**屏幕中心为锚缩放并夹紧在可见桌面内。
- **设置**：菜单栏图标 → **设置…**，可调整穿透、巡逻、缩放；选项写入 `UserDefaults`，重启后保留。同一面板底部可打开 **智能体与触发器设置**（独立窗口）。
- **饲养与陪伴**：心情/能量条、喂食与戳戳（带冷却）、宠物可见时累计「今日陪伴」秒数；数据 `UserDefaults` 持久化。
- **智能体对话**：对话面板内发消息调用 **OpenAI 兼容** `POST …/v1/chat/completions`（非流式）；`AgentClient` 使用 `Bearer` 鉴权。在「连接」Tab 可选择 **当前服务商**（预设：DeepSeek、通义千问 DashScope **兼容模式**、自定义），各自独立保存 Base URL、模型 id 与钥匙串 Key；未配置当前 Key 或网络错误时界面有提示。**多会话频道**与消息通过 `UserDefaults`（Codable）持久化；条件触发旁白另存**旁白历史**（与手动会话分轨）。用户/助手气泡与条件触发云朵气泡对模型返回的 **Markdown 内联语法**（如 `**加粗**`、`*斜体*`）做轻量渲染（`InlineMarkdownBubble`）。
- **触发器**：支持定时、随机空闲、键盘模式子串、前台应用名变化、**截屏（ScreenCaptureKit 主显示器 + 多模态 API）**；每条规则独立冷却。键盘模式与「请求附带键入摘要」属敏感能力，默认关并在设置中有说明；截屏需「隐私」总开关 + 系统**屏幕录制**权限，默认规则关闭；模型若不接受图像会在 HTTP 400 时自动改为纯文字重试一次。截屏 JPEG 可在规则内选择长边上界 **768～2048 px**；发给模型的画面元数据时间戳使用**本机时区** ISO8601。菜单栏「截屏并旁白」与设置内「立即触发」共用管线，并避免静默失败（占线 / 未保存 Key 等会提示）。
- **旁白路由（按触发器配置）**：在「智能体设置 → 触发器 → 编辑」中可为每条规则配置多条「旁白路由」：每条含 **优先级**（数字越大越先匹配）、**AND 条件组**（如按键缓冲包含某子串、前台名包含、空闲秒数、距上次触发分钟等）与 **发给模型的 user 模板**（支持 `{extra}`、`{triggerKind}`、`{matchedCondition}`、`{keySummary}` 占位）。无路由命中时使用「默认旁白请求」模板；键盘/前台仍保留旧版单字段作为「仅当路由表为空」时的回退。

## 分发与沙盒

当前目标为**非 Mac App Store**（本地自用 / Developer ID）。工程内 **`ENABLE_APP_SANDBOX = NO`**，以便全局键盘监听与桌宠交互；若日后上架 Mac App Store，需重新评估沙盒能力与权限组合。

## 代码结构（摘要）

```text
DesktopPet/
├── App/                 # AppDelegate、AppCoordinator（生命周期与模块编排）
├── Core/
│   ├── Window/          # PetWindow(NSPanel)、PetWindowController、ExtensionOverlayController、…
│   ├── Agent/           # AgentClient、AgentSettingsStore（多服务商槽位）、AgentSessionStore、多频道持久化、旁白历史、触发引擎、Keychain（按服务商分账户）
│   ├── Capture/        # ScreenCaptureService（SCK 单次截屏 → JPEG）
│   ├── Care/            # PetCareState、PetCareModel（饲养持久化与计时）
│   ├── Animation/       # AnimationDriver（状态到展示占位，可替换为序列帧/视频）
│   ├── Permissions/     # 辅助功能检测
│   ├── Input/           # GlobalInputMonitor（keyDown/keyUp、⌘K）、MouseTracker
│   ├── PetState/        # 状态机、巡逻调度
│   └── Models/          # PetConfig、DeskMirrorModel、PhysicalKeyLayout、InteractionEvent 等
├── Features/
│   ├── PetView/         # PetSpriteView、DeskMirrorTextView、DeskMirrorKeyImage、…
│   ├── Overlay/         # CareOverlayView、ChatOverlayView、AgentSettingsView、TriggerSpeechBubbleView
│   ├── Onboarding/      # 权限说明 SwiftUI 视图
│   └── Settings/        # 设置表单与持久化 ViewModel
├── Resources/
│   └── DeskMirror/      # 桌镜 Bundle 文件夹引用：cover / nohand_cover、left-keys、right-keys（PNG）
└── Utils/               # Logger、ScreenGeometry、InlineMarkdownBubble（气泡/对话内联 Markdown）
```

## 桌前镜像（桌镜）

- 宠物卡片内默认展示 **整幅叠层**：底图（空闲 `cover.png` / 有输入 `nohand_cover.png`）+ 与底图同尺寸的 **爪印 PNG**（`left-keys`，按 `NSEvent.keyCode` 映射）+ **鼠标四向**（`right-keys` 的 `UpArrow` 等）；资源位于 **`DesktopPet/Resources/DeskMirror/`**，由 Xcode **文件夹引用** 打进 Bundle。
- **键鼠逻辑**：需辅助功能；`GlobalInputMonitor` 同时监听 **keyDown / keyUp**（本应用前台用 local monitor，其它应用前台用 global）。鼠标由 `MouseTracker` 差分得到主方向（上/下/左/右）；展示层在输入停止后 **约 0.3 秒** 再回落，且静止采样不会反复重置鼠标计时器。
- **设置**：「关闭按键镜像」等见 `SettingsViewModel` / 设置面板；无权限时桌镜区有降级文案。
- **素材来源与许可**：当前 PNG 命名对齐参考工程 BongoCat 的 `keyboard/resources`；**分发前请自行确认** Live2D / 第三方素材是否允许随应用使用。

## 扩展功能（饲养与智能体）

以下能力**不替代**桌镜主卡片，叠加面板锚定在宠物窗口旁，可通过菜单栏独立显隐。

| 能力 | 说明 |
|------|------|
| 饲养面板 | `PetCareModel` / `PetCareState`：`UserDefaults` 持久化；心情与能量条、喂食（长冷却）与戳戳（短冷却）、宠物**可见**时累计今日陪伴秒数；跨日自动重置当日陪伴并小幅回补数值。 |
| 对话面板 | `ChatOverlayView` + `AgentSessionStore`（代理 `AgentConversationStore`）：非流式 `POST …/v1/chat/completions`（`AgentClient`）；仅向 API 发送 `user`/`assistant` 角色消息；`system` 类说明仅本地展示。支持**多会话频道**（切换 / 新建 / 重命名 / 删除），**UserDefaults 持久化**。 |
| 触发旁白气泡 | 条件触发得到的回复写入 **`TriggerSpeechHistoryStore`**，并以**云朵气泡**挂在宠窗附近；布局规则同上。**轻点气泡**会先收起气泡，再以该旁白为**上文**新建一个手动会话频道，并**打开对话面板**续聊（使用 `presentChatPanel`，避免误关已打开的面板）。约 14 秒无操作也会自动收起气泡。 |
| 智能体设置 | 独立窗口（多 Tab）：**连接**（当前服务商、各套 Base URL/模型、温度、max_tokens）、人格（系统提示词）、触发器列表（增删改、冷却与各类型参数）、隐私（键入摘要、键盘总闸、截屏总开关）。 |
| API Key | `KeychainStore` 按 **服务商账户** 读写（与旧版单一 DeepSeek 条目兼容迁移），**不写入** `UserDefaults`。 |
| 触发器 | `AgentTriggerEngine`：定时、随机空闲、键盘子串、前台应用名（`FrontmostAppWatcher`）、**截屏**（`ScreenCaptureService` + `AgentClient` 多模态 `user`）；每条规则 `cooldown`；截屏成功后才更新「上次触发」。成功时写入旁白历史并由 `ExtensionOverlayController.showTriggerBubble` 展示气泡。菜单栏提供「截屏并旁白一次…」。 |

**首次使用建议**：菜单栏 → **智能体设置…** → **连接** Tab 选择服务商（如 DeepSeek 或通义千问兼容模式）→ 核对 Base URL 与模型 id（千问兼容基址示例：`https://dashscope.aliyuncs.com/compatible-mode`，勿手拼 `/v1/chat/completions`）→ **保存到钥匙串**（仅作用于当前服务商）→ 打开 **对话面板** 试发一条。无网络或 Key 无效时，错误文案显示在输入区上方。

**隐私提示**：「附带键入摘要」会把桌镜生成的键位标签摘要拼进系统提示（**手动对话**与**触发旁白**请求 API 时均可能带上）；「键盘模式触发」需在隐私 Tab 开启总闸并经二次确认；「截屏类触发」会经用户为**当前服务商**配置的 API 上传**压缩后的主显示器截图**（需屏幕录制权限）。以上敏感项默认关闭。详见 [`docs/TODO_AGENT_AND_CARE.md`](docs/TODO_AGENT_AND_CARE.md)、[`docs/SCREEN_SNAP_TRIGGER_SPEC.md`](docs/SCREEN_SNAP_TRIGGER_SPEC.md) 与设置内文案。

**对话与触发是不是一条通道？** 手动对话在**当前选中的会话频道**里持久化（`AgentConversationStore`）。条件触发的模型回复先入**旁白历史**，再以气泡展示；**不会**自动追加到当前手动频道。若用户**点击气泡**，会**新建**一个频道并把该旁白作为**assistant 上文**（及一条本地 system 提示）写入后再打开对话面板，便于续聊。

**命令行编译示例**（可选，DerivedData 放在仓库内便于清理）：

```bash
xcodebuild -scheme DesktopPet -configuration Debug -derivedDataPath ./build/DerivedData build
```

## 常见问题（Xcode 控制台）

- **`NSXPCDecoder` / `NSSecureCoding` / `Allowed class list` 含 `NSObject`**：多为 **macOS 系统或 SwiftUI（菜单栏场景、`Settings`、窗口服务）** 在 XPC 解码时的内部告警，**不一定来自本仓库业务代码**。本工程已对各 `NSWindow` / `NSPanel` 设置 **`isRestorable = false`**，以降低与窗口状态恢复相关的噪声；若仍偶发出现，可在 Xcode 控制台按进程过滤 **DesktopPet**，或忽略该条（Apple 文档称未来可能升级为硬错误，届时需随系统/SDK 更新）。
- **`decode: bad range`**：常与上述系统侧解码或调试器注入有关；若应用界面与功能正常，一般可视为良性日志。

## 文档索引

| 文档 | 说明 |
|------|------|
| [`docs/requirements.md`](docs/requirements.md) | 需求文档（PRD） |
| [`docs/TODO.md`](docs/TODO.md) | **未完成**事项与后续工作（已实现内容不再在此重复罗列） |
| [`docs/TODO_AGENT_AND_CARE.md`](docs/TODO_AGENT_AND_CARE.md) | 饲养、智能体、叠加 UI、触发器与合规对照 |
| [`docs/SCREEN_SNAP_TRIGGER_SPEC.md`](docs/SCREEN_SNAP_TRIGGER_SPEC.md) | 截屏触发规格 |
| [`docs/UI_CONVENTIONS.md`](docs/UI_CONVENTIONS.md) | UI 约定 |
| [`docs/SECURITY_AND_PRIVACY.md`](docs/SECURITY_AND_PRIVACY.md) | **安全与隐私**：密钥不落库、推送前自检命令 |

## 安全与隐私（贡献者）

- API Key 与 Slack Token **仅保存在本机钥匙串**，不写入 `UserDefaults` 或仓库；推送前请阅读 [`docs/SECURITY_AND_PRIVACY.md`](docs/SECURITY_AND_PRIVACY.md) 并按文中命令自检。
- 用户侧敏感能力说明见上文 **隐私提示** 与设置内文案。

## 许可证

本项目以 [MIT License](LICENSE) 授权。
