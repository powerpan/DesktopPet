# DesktopPet

基于 Swift + SwiftUI + AppKit 的 macOS 桌面宠物项目骨架。  
当前版本已完成核心架构分层（窗口、权限、输入、状态机、设置）并保留可扩展实现位点。

## 环境要求

- macOS 14.0+
- Xcode（建议最新稳定版）
- Swift 5+
- 已安装并切换到完整 Xcode Toolchain（非仅 Command Line Tools）

## 快速开始

1. 克隆仓库

   ```bash
   git clone https://github.com/powerpan/DesktopPet.git
   cd DesktopPet
   ```

2. 用 Xcode 打开 `DesktopPet.xcodeproj`
3. 选择 `My Mac` 运行（⌘R）
4. 首次运行时，按引导开启“辅助功能”权限（Accessibility）

## 当前代码结构

```text
DesktopPet/
├── App/                # 应用入口与协调器
├── Core/
│   ├── Window/         # 浮动透明窗口、穿透控制
│   ├── Permissions/    # 辅助功能权限检测与请求
│   ├── Input/          # 全局键盘监听、鼠标追踪、快捷键
│   ├── PetState/       # 状态机与巡逻调度
│   └── Models/         # 配置与交互事件模型
├── Features/
│   ├── PetView/        # 宠物容器、精灵视图、悬浮设置按钮
│   └── Settings/       # 设置面板与 ViewModel
└── Utils/              # 日志与屏幕几何工具
```

## 关键能力（骨架已就位）

- 透明无边框顶层窗口（`.floating`）
- 全局键盘监听入口（需辅助功能权限）
- 鼠标追踪入口与交互事件模型
- `Cmd+K` 快捷键监听入口
- 宠物状态机（idle / walk / keyTap / jump / sleep）

## 下一步开发建议

1. 将新建骨架文件加入 `project.pbxproj` 的编译目标（当前仅仓库结构完成）
2. 将 `PetContainerView` 接入 `PetWindowController` 的点击穿透状态同步
3. 完成动画驱动层（序列帧 / GIF / HEVC Alpha）与状态机联动
4. 实现巡逻路径与活动窗口顶部贴边策略
5. 增加单元测试：`PetStateMachine`、`PatrolScheduler`、权限流程

## 需求文档

- 详细 PRD：`docs/requirements.md`

## 许可证

待补充（建议 MIT）。
