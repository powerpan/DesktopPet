# DesktopPet 待办 / 后续工作

> 与 `docs/requirements.md` 对照的**缺口与后续工作**清单。已在主分支落地的能力见 `README.md` 与 PRD §9 验收清单；本文件只保留未勾选或可选项。

## 产品方向（与当前实现对齐）

- **默认**：宠物卡片内为**桌前键盘 + 鼠标垫镜像**（`PetSpriteView` / `DeskMirrorTextView` 等），不依赖序列帧资源即可用。
- **拖动窗口时**：切换为**猫猫动作序列**（序列帧或 GIF 先打通一种）；松手拖回桌镜 UI。
- **注意**：巡逻、`petScale` 缩放等会**程序化 `setFrame`**，需与用户拖窗区分（见中优先级「拖动静默」），避免拖一半误切桌镜或误播动画。

## 高优先级

- [ ] **拖窗检测 + 展示切换**：`PetWindow` / `PetWindowController`（或 `NSWindowDelegate`）维护「用户正在拖动」状态（`ObservableObject` / `Environment` 注入 `PetContainerView`）；`PetSpriteView` 按状态在 **桌镜根布局** 与 **动画视图** 间切换。
- [ ] **拖动专用动画管线**：首版只需 **一套循环序列**（如 `drag_loop`）；用 `Timer`/`TimelineView`/`Image` 轮播或 `NSImage` 绑定；缺失资源时降级为当前大字/占位图。
- [ ] **资源与加载路径**：在工程内增加 **`DesktopPet/Resources/Animations/`**（或 Xcode **Folder Reference** 指向该目录），首版子目录示例：`Drag/` 下放 `frame_0001.png` … 或单文件 `drag.gif`；**不必**先铺满 `idle/walk/keyTap` 全状态。`Assets.xcassets` 继续留给 **App Icon / AccentColor**；大量帧图优先放 **Bundle 子目录** 以免 asset catalog 臃肿。
- [ ] **与状态机的关系（二期）**：巡逻 `walk`、敲击 `keyTap` 等是否也在非桌镜模式下播动画，与「仅拖窗播」可拆分里程碑；`PetAnimationDriver` 可演进为「桌镜文案 + 资源名映射」的薄层。
- [ ] **单元测试**：新增 Test 目标；至少覆盖 `PetStateMachine` 迁移、巡逻边界/可见区、`PetConfig.exteriorHitSide` 与缩放锚点相关逻辑（可选）。

## 中优先级

- [ ] **拖动静默与程序化位移**：`applyWindowSize` / `nudgePatrolStep` 打标期间不视为用户拖动；必要时在 `setFrame` 前后短暂屏蔽 `windowDidMove` 推断。
- [ ] **鼠标互动打磨**：按距离、速度、停留时间细化触发阈值；验收「接近/远离自然、无高频抖动」（PRD F3）。
- [ ] **巡逻与 walk**：巡逻节奏与 `walk` 状态/动画语义对齐；巡逻间隔可进设置（当前多为常量）。
- [ ] **无辅助功能降级**：明确无权限时的行为（仅本地键、仅菜单提示等）并写进 README/PRD。
- [ ] **多屏 / Space / 全屏回归**：验证 `collectionBehavior`、外接显示器、深色模式；必要时增加「按配置」的 Space 行为开关（PRD F1）。
- [ ] **菜单栏热点避让**：巡逻/落点不长期压在菜单栏关键交互区（PRD F6 验收）。

## 低优先级 / 产品扩展

- [ ] **动画模式切换**：设置中切换「序列帧 / 视频」等（PRD 配置项）；对应 `AnimationDriver` 多后端。
- [ ] **快捷键自定义**：除默认 ⌘K 外支持用户改键并持久化。
- [ ] **性能与可观测性**：空闲 CPU、监听与动画解耦的采样或简单日志基准（PRD 6.3）。
- [ ] **权限流测试**：UI 或集成测试覆盖 onboarding + 重检（可选）。

## 工程与发布

- [x] **README 许可证**：已添加根目录 `LICENSE`（MIT），README 已链接。
- [ ] **验收清单**：发版前按 `docs/requirements.md` §9 与 `README` 快速回归一遍。
- [ ] **PRD 结构树**：若新增模块，同步更新 PRD §10 目录树（避免与源码漂移）。
- [ ] **分发**（若对公众发布）：Developer ID 签名、公证、分发说明；若考虑 Mac App Store，需单独评估沙盒与权限方案。
