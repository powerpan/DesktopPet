# DesktopPet 需求文档（PRD）

> **仓库实现备注（2026）**：当前工程已关闭 App Sandbox，采用菜单栏 accessory 形态启动；宠物窗口为 `NSPanel` 浮动层（`PetWindow` / `PetWindowController`），全局键盘与 `⌘K` 通过 `GlobalInputMonitor` 单路监听；设置项已接入 `UserDefaults`。**Bundle ID** 为 `io.github.powerpan.DesktopPet`；生成 Info 时含 `NSAccessibilityUsageDescription`。辅助功能未授权时由 `AccessibilityPermissionManager` 与 `AccessibilityOnboardingView` 引导登记 TCC、`AppCoordinator` 在激活与「重新检测」后延迟轮询信任状态。  
> **窗口与命中**：`PetConfig.petCanvasLayoutPoints`（卡片基准边长）、`petScaleMin`/`petScaleMax`（缩放滑条范围，当前最大 1.2）、`exteriorHitSide` 与 `visualBaselineFactor` 统一窗口边长与 `PetRootContainerView.hitClipSidePoints`；穿透开启时精灵层不接收点击，包络外 `hitTest` 为 `nil`。拖动缩放滑条时以固定屏幕锚点缩放并夹紧 `visibleFrame`。细节以 `README.md` 与源码为准。

## 1. 项目概述

DesktopPet 是一个完全本地运行的 macOS 原生桌面宠物系统，使用 Swift + SwiftUI + AppKit 实现。宠物以透明、无边框、常驻顶层窗口形式展示，核心价值是为用户提供轻量互动与陪伴，同时尽量减少对日常操作的干扰。

## 2. 目标与范围

### 2.1 目标

- 提供稳定、低侵入的桌面宠物常驻体验。
- 将键盘与鼠标行为映射为宠物动画反馈，形成即时互动。
- 提供最小可用设置能力（显示/隐藏、穿透切换、拖动定位）。
- 保持离线可用与本地隐私安全，不依赖云端服务。

### 2.2 非目标（当前阶段）

- 多宠物并行与宠物养成系统。
- 跨平台支持（Windows/Linux）。
- 云同步、账号系统、联网内容分发。

## 3. 用户场景

- 用户写代码/文档时持续敲击键盘，猫咪做敲击反馈。
- 用户移动鼠标靠近宠物时，猫咪跟随、注视或跳跃。
- 用户需要操作宠物位置时，临时关闭鼠标穿透进行拖动。
- 用户希望快速隐藏/唤出宠物，使用快捷键 Cmd+K 控制可见性。

## 4. 功能需求

### F1 顶层透明宠物窗口

- 采用无边框、透明背景窗口展示宠物。
- 窗口层级固定为 `.floating`，尽可能保持可见。
- 需支持在多桌面/空间切换时维持一致行为（按配置启用）。

验收标准：
- 应用切换后宠物仍可见。
- 宠物窗口不出现标题栏、阴影异常、背景色块。

### F2 全局键盘监听与动画反馈

- 首次获得 Accessibility 权限后监听全局键盘事件。
- 键盘输入触发猫咪敲击状态动画（可按频率增强节奏感）。

验收标准：
- 连续输入时有稳定动画反馈，明显低延迟。
- 无权限时提供降级行为与明确提示。

### F3 鼠标互动（跟随/注视/跳跃）

- 采集鼠标位置并计算与宠物的相对关系。
- 根据距离、速度、停留时间触发不同交互动作。

验收标准：
- 鼠标接近与远离时动画状态切换自然。
- 不出现高频抖动或异常跳变。

### F4 鼠标穿透与设置按钮

- 默认可开启鼠标穿透，不阻挡下层应用点击。
- 保留一个可点击设置按钮（与系统设置面板中的穿透开关绑定同一状态），用于切换穿透；关闭穿透后可拖背景移动窗口。

验收标准：
- 穿透开启时：精灵主区域不接收命中；仅保留必要控件（如右上角切换）可点；窗口外圈与缩放后的「空白外圈」不应长期挡住下层点击（`PetSpriteView` + `PetRootContainerView` 包络命中 + 窗口尺寸与 `exteriorHitSide` 一致）。
- 穿透关闭后可拖动窗口且拖动体验稳定。

### F5 快捷键显示/隐藏

- 支持全局快捷键 `Cmd+K` 切换宠物显示状态。

验收标准：
- 前台应用变化不影响快捷键触发成功率。

### F6 随机巡逻

- 猫咪会随机在屏幕边缘或活动窗口顶部巡逻。
- 巡逻可被用户输入事件打断并恢复。

验收标准：
- 巡逻路径始终在可见区域内。
- 不遮挡系统关键交互区域（如菜单栏主交互热点）。

## 5. 状态机设计

状态集合：`idle`、`walk`、`keyTap`、`jump`、`sleep`

- `idle`：默认待机，微动作循环。
- `walk`：执行巡逻路径。
- `keyTap`：接收键盘事件后短时动作。
- `jump`：鼠标互动触发跳跃。
- `sleep`：长时间无输入进入休眠。

关键状态迁移：

- `idle -> keyTap`（键盘输入）
- `idle -> walk`（巡逻调度）
- `walk -> keyTap`（输入打断）
- `idle/walk -> jump`（鼠标互动触发）
- `idle -> sleep`（长时间空闲）
- `sleep -> idle`（任意输入）

## 6. 技术方案

### 6.1 技术栈

- 语言：Swift 5+
- UI：SwiftUI
- 系统能力与窗口管理：AppKit
- 动画：NSImageView（GIF/序列帧）或 AVPlayer（HEVC Alpha）

### 6.2 模块职责

- `Window`：窗口创建、层级、穿透、拖动行为。
- `Permissions`：辅助功能权限检查与引导。
- `Input`：全局键盘监听、鼠标追踪、快捷键注册。
- `Animation`：动画资源加载与统一播放接口。
- `PetState`：状态机、状态切换与巡逻调度。
- `Features`：视图层与设置面板。

### 6.3 性能与可靠性要求

- 空闲时 CPU 占用保持低水平（通过采样降频与动画降级实现）。
- 事件监听与动画调度解耦，避免主线程阻塞。
- 权限缺失、素材缺失、窗口重建失败时可恢复或明确提示。

## 7. 权限处理与隐私

### 7.1 首次启动流程

1. 启动时检查 Accessibility 授权状态（`AXIsProcessTrustedWithOptions`，默认不弹系统提示框）。
2. 未授权时展示用途说明与引导入口；可触发一次带 `prompt` 的检查以将应用写入系统「辅助功能」列表。
3. 用户跳转系统设置后，应用回前台重新检测；支持「重新检测」与短时延迟轮询，缓解 TCC 同步延迟。
4. 授权成功后激活/重启全局键盘监听。

### 7.2 隐私原则

- 不采集输入文本内容，仅处理事件级别信号（按键发生）。
- 不上传行为数据，默认仅本地运行。

## 8. 配置项（建议）

- 宠物显隐（快捷键）
- 鼠标穿透开关
- 巡逻开关与频率
- 动画模式（序列帧/视频）
- 窗口尺寸与缩放比例（实现：`PetConfig.exteriorHitSide` + `visualBaselineFactor`，与 `PetWindowController` 联动）

## 9. 验收清单

- [ ] 宠物窗口透明、无边框、顶层显示正常
- [ ] 辅助功能权限引导流程可用
- [ ] 键盘输入触发动画反馈
- [ ] 鼠标互动行为稳定
- [ ] 穿透与拖动切换正确
- [ ] Cmd+K 全局快捷键可用
- [ ] 巡逻逻辑自然且不越界

## 10. 推荐项目结构

```text
DesktopPet/
├── App/
│   ├── DesktopPetApp.swift
│   ├── AppDelegate.swift
│   └── AppCoordinator.swift
├── Core/
│   ├── Window/
│   │   ├── PetWindowController.swift
│   │   ├── PetWindow.swift
│   │   ├── PetRootContainerView.swift
│   │   └── HitTestPassthroughView.swift
│   ├── Permissions/
│   │   └── AccessibilityPermissionManager.swift
│   ├── Input/
│   │   ├── KeyboardMonitor.swift
│   │   ├── MouseTracker.swift
│   │   └── GlobalHotkeyManager.swift
│   ├── Animation/
│   │   ├── AnimationDriver.swift
│   │   ├── SpriteSequencePlayer.swift
│   │   ├── GIFPlayer.swift
│   │   └── AlphaVideoPlayer.swift
│   ├── PetState/
│   │   ├── PetState.swift
│   │   ├── PetStateMachine.swift
│   │   └── PatrolScheduler.swift
│   └── Models/
│       ├── PetConfig.swift
│       └── InteractionEvent.swift
├── Features/
│   ├── PetView/
│   │   ├── PetContainerView.swift
│   │   ├── PetSpriteView.swift
│   │   └── SettingsFloatingButton.swift
│   └── Settings/
│       ├── SettingsPanelView.swift
│       └── SettingsViewModel.swift
├── Resources/
│   ├── Animations/
│   │   ├── idle/
│   │   ├── walk/
│   │   ├── keytap/
│   │   ├── jump/
│   │   └── sleep/
│   └── Audio/
├── Utils/
│   ├── Logger.swift
│   └── ScreenGeometry.swift
└── Tests/
    ├── PetStateMachineTests.swift
    ├── PatrolSchedulerTests.swift
    └── PermissionFlowTests.swift
```

## 11. 里程碑建议

- M1：窗口层级与透明无边框基础能力
- M2：权限闭环与全局键盘监听
- M3：状态机 + 动画管线
- M4：鼠标互动与巡逻
- M5：设置面板与稳定性优化
