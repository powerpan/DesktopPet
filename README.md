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

- **菜单栏**：点击爪印图标可显示/隐藏宠物、**显示/隐藏饲养面板**、**显示/隐藏对话面板**、打开**智能体设置**（DeepSeek API Key 存钥匙串、触发器与隐私开关）、打开权限说明、进入系统「设置…」面板（`⌘,`）、退出应用。
- **桌镜卡片**：标题为 **「七七猫1.0」**；底部保留 **英文** 状态枚举名（如 `idle`、`keyTap`）；键入历史为单行摘要，与桌镜图叠层分离布局。
- **⌘K**：全局快捷键，切换宠物窗口显示（需已授予辅助功能）。
- **鼠标穿透**：菜单栏 **设置…** 与窗口右上角按钮共用同一开关。开启时精灵区不参与命中；`PetRootContainerView` 包络外 `hitTest` 为 `nil`，包络内只转发 `NSHostingView.hitTest`（**不用** `?? hostingView`）。`PetSpriteView` 使用与圆角一致的 `contentShape`。宠物根视图**不再**整卡 `.padding(8)`，窗口边长由 `PetConfig.exteriorHitSide` 取「视觉边长 + 约 6pt」以尽量消掉隐形外圈。穿透关闭时拖窗请点在**材质卡片**上。
- **缩放**：滑条 **0.6～1.2**（最大整窗约等于此前仅拉到 1.2× 时的体量，不再支持 1.8）。卡片画布基准 **176pt**（`PetConfig.petCanvasLayoutPoints`，小于原 220）以减小占位。`visualBaselineFactor`（0.6）仍使 **1.0 档** 视觉约等于更早一版「相对 0.6」的体量。连续拖动滑条时窗口以**本轮第一次**屏幕中心为锚缩放并夹紧在可见桌面内。
- **设置**：菜单栏图标 → **设置…**，可调整穿透、巡逻、缩放；选项写入 `UserDefaults`，重启后保留。同一面板底部可打开 **智能体与触发器设置**（独立窗口）。
- **饲养与陪伴**：心情/能量条、喂食与戳戳（带冷却）、宠物可见时累计「今日陪伴」秒数；数据 `UserDefaults` 持久化。
- **智能体对话**：对话面板内发消息调用 DeepSeek 兼容 `chat/completions`（非流式）；未配置 Key 或网络错误时界面有提示。
- **触发器**：支持定时、随机空闲、键盘模式子串、前台应用名变化；每条规则独立冷却。键盘模式与「请求附带键入摘要」属敏感能力，默认关并在设置中有说明；截屏类触发为占位，当前不会发起截屏。

## 分发与沙盒

当前目标为**非 Mac App Store**（本地自用 / Developer ID）。工程内 **`ENABLE_APP_SANDBOX = NO`**，以便全局键盘监听与桌宠交互；若日后上架 Mac App Store，需重新评估沙盒能力与权限组合。

## 代码结构（摘要）

```text
DesktopPet/
├── App/                 # AppDelegate、AppCoordinator（生命周期与模块编排）
├── Core/
│   ├── Window/          # PetWindow(NSPanel)、PetWindowController、ExtensionOverlayController、…
│   ├── Agent/           # AgentClient、AgentSettingsStore、AgentSessionStore、触发引擎、Keychain
│   ├── Care/            # PetCareState、PetCareModel（饲养持久化与计时）
│   ├── Animation/       # AnimationDriver（状态到展示占位，可替换为序列帧/视频）
│   ├── Permissions/     # 辅助功能检测
│   ├── Input/           # GlobalInputMonitor（keyDown/keyUp、⌘K）、MouseTracker
│   ├── PetState/        # 状态机、巡逻调度
│   └── Models/          # PetConfig、DeskMirrorModel、PhysicalKeyLayout、InteractionEvent 等
├── Features/
│   ├── PetView/         # PetSpriteView、DeskMirrorTextView、DeskMirrorKeyImage、…
│   ├── Overlay/         # CareOverlayView、ChatOverlayView、AgentSettingsView
│   ├── Onboarding/      # 权限说明 SwiftUI 视图
│   └── Settings/        # 设置表单与持久化 ViewModel
├── Resources/
│   └── DeskMirror/      # 桌镜 Bundle 文件夹引用：cover / nohand_cover、left-keys、right-keys（PNG）
└── Utils/
```

## 桌前镜像（桌镜）

- 宠物卡片内默认展示 **整幅叠层**：底图（空闲 `cover.png` / 有输入 `nohand_cover.png`）+ 与底图同尺寸的 **爪印 PNG**（`left-keys`，按 `NSEvent.keyCode` 映射）+ **鼠标四向**（`right-keys` 的 `UpArrow` 等）；资源位于 **`DesktopPet/Resources/DeskMirror/`**，由 Xcode **文件夹引用** 打进 Bundle。
- **键鼠逻辑**：需辅助功能；`GlobalInputMonitor` 同时监听 **keyDown / keyUp**（本应用前台用 local monitor，其它应用前台用 global）。鼠标由 `MouseTracker` 差分得到主方向（上/下/左/右）；展示层在输入停止后 **约 0.3 秒** 再回落，且静止采样不会反复重置鼠标计时器。
- **设置**：「关闭按键镜像」等见 `SettingsViewModel` / 设置面板；无权限时桌镜区有降级文案。
- **素材来源与许可**：当前 PNG 命名对齐参考工程 BongoCat 的 `keyboard/resources`；**分发前请自行确认** Live2D / 第三方素材是否允许随应用使用。

## 已实现行为（相对上一版骨架）

- 启动后由 `AppCoordinator` 创建宠物窗口；无独立 `WindowGroup` 主窗口，避免与桌宠双窗口干扰。
- 全局 `keyDown` 单路监听；`⌘K` 与「敲击」反馈分流。
- 巡逻定时器在可见桌面范围内随机移动宠物窗口；约一半概率尝试贴近**当前前台其他应用窗口**上沿（基于 `CGWindowListCopyWindowInfo`，无额外权限时亦常可用）。
- 鼠标靠近仍可唤醒睡眠态等逻辑，但**不再**对精灵层做水平位移，避免画面随光标晃动。
- 连续打字会略**缩短敲击态**停留时间，反馈更跟手。
- 睡眠态下不再重设「进入睡眠」的空闲计时器，避免无意义重复触发。
- 空闲约 `PetConfig.default.idleToSleepInterval` 秒后进入睡眠状态；键鼠或巡逻可唤醒。
- 设置项（穿透、巡逻、缩放）持久化。
- 辅助功能：`AXIsProcessTrusted` 诊断文案、`tccutil` 与签名自检说明；未授权时延迟登记 TCC 列表与多次重检；`PetWindow` 允许必要时成为 key 以避免 `makeKeyWindow` 控制台告警。
- **桌前镜像**：`DeskMirrorTextView` 整幅 `cover` / `nohand_cover` 与爪印、鼠标方向 PNG 同比例叠放；`DeskMirrorKeyImage` 负责 Bundle 路径与宽高比；`DeskMirrorModel` 维护物理高亮、展示层延迟与鼠标方向防抖。
- **饲养 / 智能体 / 叠加窗**：由 `ExtensionOverlayController` 锚定在宠窗旁；`AppCoordinator` 编排 `PetCareModel`、`AgentTriggerEngine`、`FrontmostAppWatcher` 与键鼠活动采样；`⌘K` 与桌镜主流程保持独立。

## 扩展功能（饲养与智能体）

以下能力**不替代**桌镜主卡片，叠加面板锚定在宠物窗口旁，可通过菜单栏独立显隐。

| 能力 | 说明 |
|------|------|
| 饲养面板 | `PetCareModel` / `PetCareState`：`UserDefaults` 持久化；心情与能量条、喂食（长冷却）与戳戳（短冷却）、宠物**可见**时累计今日陪伴秒数；跨日自动重置当日陪伴并小幅回补数值。 |
| 对话面板 | `ChatOverlayView` + `AgentSessionStore`：非流式 `POST …/v1/chat/completions`（`AgentClient`）；仅向 API 发送 `user`/`assistant` 角色消息；系统提示词可在设置中编辑。**会话只在内存中**，关闭对话面板或退出应用即清空（无多轮历史持久化）。 |
| 触发旁白气泡 | 条件触发得到的回复以**云朵气泡**挂在宠窗附近；默认在猫猫**上方**居中；当宠窗靠近屏幕**右侧且下侧**（约 130pt 内）时改挂到猫猫**左上侧**，并夹在安全区内。轻点气泡或约 14 秒后消失；**不写入**对话列表。 |
| 智能体设置 | 独立窗口（多 Tab）：连接（Base URL、模型、温度、max_tokens）、人格（系统提示词）、触发器列表（增删改、冷却与各类型参数）、隐私（键入摘要、键盘总闸、截屏占位开关）。 |
| API Key | `KeychainStore` 读写，**不写入** `UserDefaults`。 |
| 触发器 | `AgentTriggerEngine`：定时、随机空闲、键盘子串匹配（仅内存环形缓冲，不落盘原文）、前台应用名子串（`FrontmostAppWatcher`）；每条规则 `cooldown`；截屏类型为占位，当前**不会**请求截屏权限或上传图像。成功时由 `ExtensionOverlayController.showTriggerBubble` 展示旁白。 |

**首次使用建议**：菜单栏 → **智能体设置…** → 填写 Base URL（默认 `https://api.deepseek.com`）与模型名 → **保存到钥匙串** → 打开 **对话面板** 试发一条。无网络或 Key 无效时，错误文案显示在输入区上方。

**隐私提示**：「附带键入摘要」会把桌镜生成的键位标签摘要拼进系统提示（**手动对话**与**触发旁白**请求 API 时均可能带上）；「键盘模式触发」需在隐私 Tab 开启总闸并经二次确认；二者默认关闭。详见 [`docs/TODO_AGENT_AND_CARE.md`](docs/TODO_AGENT_AND_CARE.md) 与设置内文案。

**对话与触发是不是一条通道？** 手动在对话面板发的消息在同一条 `AgentSessionStore.messages` 列表里，仅内存、无按日期分会话的存档。条件触发的模型回复**只走云气泡**，不再追加到该列表，避免和聊天混成一串。

**命令行编译示例**（可选，DerivedData 放在仓库内便于清理）：

```bash
xcodebuild -scheme DesktopPet -configuration Debug -derivedDataPath ./build/DerivedData build
```

## 常见问题（Xcode 控制台）

- **`NSXPCDecoder` / `NSSecureCoding` / `Allowed class list` 含 `NSObject`**：多为 **macOS 系统或 SwiftUI（菜单栏场景、`Settings`、窗口服务）** 在 XPC 解码时的内部告警，**不一定来自本仓库业务代码**。本工程已对各 `NSWindow` / `NSPanel` 设置 **`isRestorable = false`**，以降低与窗口状态恢复相关的噪声；若仍偶发出现，可在 Xcode 控制台按进程过滤 **DesktopPet**，或忽略该条（Apple 文档称未来可能升级为硬错误，届时需随系统/SDK 更新）。
- **`decode: bad range`**：常与上述系统侧解码或调试器注入有关；若应用界面与功能正常，一般可视为良性日志。

## 需求文档

- 详细 PRD：`docs/requirements.md`
- 待办与后续工作：`docs/TODO.md`
- **扩展规划与实现对照**（饲养、智能体 DeepSeek、叠加 UI、触发器与合规待办）：`docs/TODO_AGENT_AND_CARE.md`

## 许可证

待补充（建议 MIT）。
