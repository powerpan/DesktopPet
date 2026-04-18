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

- **菜单栏**：点击爪印图标可显示/隐藏宠物、打开权限说明、进入系统「设置…」面板（`⌘,`）、退出应用。
- **桌镜卡片**：标题为 **「七七猫1.0」**；底部保留 **英文** 状态枚举名（如 `idle`、`keyTap`）；键入历史为单行摘要，与桌镜图叠层分离布局。
- **⌘K**：全局快捷键，切换宠物窗口显示（需已授予辅助功能）。
- **鼠标穿透**：菜单栏 **设置…** 与窗口右上角按钮共用同一开关。开启时精灵区不参与命中；`PetRootContainerView` 包络外 `hitTest` 为 `nil`，包络内只转发 `NSHostingView.hitTest`（**不用** `?? hostingView`）。`PetSpriteView` 使用与圆角一致的 `contentShape`。宠物根视图**不再**整卡 `.padding(8)`，窗口边长由 `PetConfig.exteriorHitSide` 取「视觉边长 + 约 6pt」以尽量消掉隐形外圈。穿透关闭时拖窗请点在**材质卡片**上。
- **缩放**：滑条 **0.6～1.2**（最大整窗约等于此前仅拉到 1.2× 时的体量，不再支持 1.8）。卡片画布基准 **176pt**（`PetConfig.petCanvasLayoutPoints`，小于原 220）以减小占位。`visualBaselineFactor`（0.6）仍使 **1.0 档** 视觉约等于更早一版「相对 0.6」的体量。连续拖动滑条时窗口以**本轮第一次**屏幕中心为锚缩放并夹紧在可见桌面内。
- **设置**：菜单栏图标 → **设置…**，可调整穿透、巡逻、缩放；选项写入 `UserDefaults`，重启后保留。

## 分发与沙盒

当前目标为**非 Mac App Store**（本地自用 / Developer ID）。工程内 **`ENABLE_APP_SANDBOX = NO`**，以便全局键盘监听与桌宠交互；若日后上架 Mac App Store，需重新评估沙盒能力与权限组合。

## 代码结构（摘要）

```text
DesktopPet/
├── App/                 # AppDelegate、AppCoordinator（生命周期与模块编排）
├── Core/
│   ├── Window/          # PetWindow(NSPanel)、PetWindowController、PetRootContainerView
│   ├── Animation/       # AnimationDriver（状态到展示占位，可替换为序列帧/视频）
│   ├── Permissions/     # 辅助功能检测
│   ├── Input/           # GlobalInputMonitor（keyDown/keyUp、⌘K）、MouseTracker
│   ├── PetState/        # 状态机、巡逻调度
│   └── Models/          # PetConfig、DeskMirrorModel、PhysicalKeyLayout、InteractionEvent 等
├── Features/
│   ├── PetView/         # PetSpriteView、DeskMirrorTextView、DeskMirrorKeyImage、…
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

## 需求文档

- 详细 PRD：`docs/requirements.md`
- 待办与后续工作：`docs/TODO.md`
- **扩展规划**（饲养、智能体 DeepSeek、叠加 UI、菜单栏触发与 API 设置）：`docs/TODO_AGENT_AND_CARE.md`

## 许可证

待补充（建议 MIT）。
