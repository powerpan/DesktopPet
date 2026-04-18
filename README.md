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
3. 在菜单栏点击 **爪印图标**，使用「辅助功能与权限说明」或首次弹窗完成 **辅助功能** 授权。
4. 系统设置中也可搜索「辅助功能」，勾选 **DesktopPet**（列表中的名称应与权限窗口底部「可执行名」一致；Xcode 调试若勾选后仍无全局键盘，请**退出应用再 Run**，并在说明窗口点 **重新检测** 查看诊断文案）。

## 使用说明

- **菜单栏**：点击爪印图标可显示/隐藏宠物、打开权限说明、进入系统「设置…」面板（`⌘,`）、退出应用。
- **⌘K**：全局快捷键，切换宠物窗口显示（需已授予辅助功能）。
- **鼠标穿透**：宠物窗口右上角按钮可切换；开启时仅按钮区域接收点击，其余穿透到下层应用（由 `PetRootContainerView` 的 hit-test 实现）。
- **设置**：菜单栏图标 → **设置…**，可调整穿透、巡逻、缩放；选项写入 `UserDefaults`，重启后保留。

## 分发与沙盒

当前目标为**非 Mac App Store**（本地自用 / Developer ID）。工程内 **`ENABLE_APP_SANDBOX = NO`**，以便全局键盘监听与桌宠交互；若日后上架 Mac App Store，需重新评估沙盒能力与权限组合。

## 代码结构（摘要）

```text
DesktopPet/
├── App/                 # AppDelegate、AppCoordinator（生命周期与模块编排）
├── Core/
│   ├── Window/          # PetWindow(NSPanel)、PetWindowController、穿透根视图
│   ├── Animation/       # AnimationDriver（状态到展示占位，可替换为序列帧/视频）
│   ├── Permissions/    # 辅助功能检测
│   ├── Input/           # GlobalInputMonitor（合并全局键与 ⌘K）、MouseTracker
│   ├── PetState/        # 状态机、巡逻调度
│   └── Models/          # 配置与交互事件
├── Features/
│   ├── PetView/         # 宠物 SwiftUI 层
│   ├── Onboarding/      # 权限说明 SwiftUI 视图
│   └── Settings/        # 设置表单与持久化 ViewModel
└── Utils/
```

## 已实现行为（相对上一版骨架）

- 启动后由 `AppCoordinator` 创建宠物窗口；无独立 `WindowGroup` 主窗口，避免与桌宠双窗口干扰。
- 全局 `keyDown` 单路监听；`⌘K` 与「敲击」反馈分流。
- 巡逻定时器在可见桌面范围内随机移动宠物窗口；约一半概率尝试贴近**当前前台其他应用窗口**上沿（基于 `CGWindowListCopyWindowInfo`，无额外权限时亦常可用）。
- 鼠标靠近时精灵层有轻微**水平注视偏移**（`PointerTrackingModel`，不改变状态枚举）。
- 连续打字会略**缩短敲击态**停留时间，反馈更跟手。
- 睡眠态下不再重设「进入睡眠」的空闲计时器，避免无意义重复触发。
- 空闲约 `PetConfig.default.idleToSleepInterval` 秒后进入睡眠状态；键鼠或巡逻可唤醒。
- 设置项（穿透、巡逻、缩放）持久化。

## 需求文档

- 详细 PRD：`docs/requirements.md`

## 许可证

待补充（建议 MIT）。
