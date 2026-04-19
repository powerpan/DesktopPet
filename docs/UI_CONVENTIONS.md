# DesktopPet UI 与前端架构约定

面向 SwiftUI 浮层、**智能体工作台**、系统设置与路由的维护说明。

---

## 信息架构（用户可见）

### 两套「设置」的职责边界

| 入口 | 窗口 / 场景 | 职责 |
|------|----------------|------|
| 菜单栏 **SettingsLink** 或 **DesktopPet 设置…** | macOS 系统 `Settings` → `SettingsPanelView` | **桌宠外观与行为**：穿透、桌镜、巡逻、缩放 |
| 菜单栏 **打开智能体工作台…**、宠窗左下角菜单、对话/饲养内快捷入口 | `NSWindow` 标题「智能体工作台」→ `AgentSettingsView` | **模型、对话内容、陪伴数值、自动化、集成**（Slack、盯屏等） |

避免在文案里笼统写「去设置」，应写清「系统设置」或「智能体工作台」。

### 菜单栏爪印（`DesktopPetApp`）

分组顺序：**显示与面板** → **智能体工作台** → **权限与帮助** → **应用**（含系统设置链接与退出）。

### 宠窗轻量入口（`PetContainerView`）

- 左下角 **⋯** 菜单：对话面板、饲养面板、智能体工作台、显隐宠物、DesktopPet 系统设置。
- 转发类：`PetHUDBridge`（弱引用 `AppCoordinator`），由 `PetWindowController` 注入 `environmentObject`，避免与 `NSHostingView` 形成强引用环。

### 智能体工作台（五分区）

`TabView` 使用 **0…4** 索引（`@AppStorage("DesktopPet.ui.agentSettingsSelectedTab")`）。分区与内容：

| 索引 | 分区名 | 根视图 | 说明 |
|------|--------|--------|------|
| 0 | 连接 | `ConnectionTabView` | 服务商、Base URL、Key、生成参数 |
| 1 | 对话 | `ConversationCenterTabView` | 内嵌 `SessionHistoryTabView` + `PersonaTabView` |
| 2 | 陪伴 | `GrowthTabView` | 成长、冷却、统计与调试 |
| 3 | 自动化 | `AutomationCenterTabView` | 内嵌 `TriggersTabView` + `PrivacyTabView` |
| 4 | 集成 | `IntegrationsTabView` | Slack、盯屏任务与事件 |

枚举与旧版索引迁移：`AgentSettingsWorkspaceTab`（`Features/Overlay/AgentSettings/AgentSettingsWorkspaceTab.swift`）。

### 旧版 7 Tab 与通知兼容

`NotificationCenter` 仍可使用 `userInfo[agentSettingsTabIndex]`，语义为 **旧版 0…6**（连接…集成）。`AppCoordinator.wirePresentAgentSettingsTabNotificationBridge` 会映射为当前 **0…4** 再调用 `routeBus.presentAgentSettingsTab`。

| 旧索引 | 旧名称 | 新工作台索引 |
|--------|--------|----------------|
| 0 | 连接 | 0 |
| 1 | 会话与历史 | 1 |
| 2 | 人格 | 1 |
| 3 | 触发器 | 3 |
| 4 | 隐私 | 3 |
| 5 | 成长 | 2 |
| 6 | 集成 | 4 |

应用内新代码请直接传 **0…4**（或 `AgentSettingsWorkspaceTab.*.rawValue`）。

### 布局版本与 `@AppStorage` 迁移

- 键：`DesktopPet.ui.agentSettingsTabLayoutVersion`，值为 `1` 表示已按五分区迁移过「上次选中 Tab」。
- 首次升级时由 `AgentSettingsWorkspaceTab.migrateSelectedTabIfNeeded` 将旧的 0…6 选中值映射为 0…4。

### 待打开分区（深链）

- 键：`DesktopPet.ui.pendingAgentSettingsTab.v2`  
- 写入方（`AppCoordinator` / `routeBus`）写入 **0…4**。若在未升级布局版本的环境写入旧语义，消费端在 `AgentSettingsView.onAppear` 中按 `layoutVersion` 分支解析（见源码）。

---

## 为什么有时「看不出变化」？

- **纯逻辑/架构**改动可能不改变视觉；信息架构改版后应能通过：**工作台五 Tab**、**菜单分组**、**宠窗 ⋯ 菜单**、**系统设置顶部说明** 感知。
- 编译与运行：见下文「推荐本地编译」；Xcode **Clean Build Folder** 后再 Run。

---

## 推荐本地编译

在仓库根目录：

```bash
xcodebuild -scheme DesktopPet -configuration Debug \
  -derivedDataPath ./.derivedData build
```

成功标志：`** BUILD SUCCEEDED **`。产物：`.derivedData/Build/Products/Debug/DesktopPet.app`。

---

## 目录与模块（代码）

| 区域 | 路径 | 说明 |
|------|------|------|
| 浮层 / 宠窗 | `DesktopPet/Features/Overlay/`、`Features/PetView/` | 对话、饲养、宠窗布局 |
| 工作台组装 | `Features/Overlay/AgentSettingsView.swift` | 五分区 `TabView`、深链与 `AppRouteBus` |
| 分区子视图 | `Features/Overlay/AgentSettings/*` | 含 `ConversationCenterTabView`、`AutomationCenterTabView` |
| 触发器共享 UI | `AgentSettingsTriggerComponents.swift` | 列表行、规则 Sheet 等 |
| 系统设置表单 | `Features/Settings/SettingsPanelView.swift` | 仅桌宠行为 |
| 应用壳与路由 | `DesktopPet/App/` | `AppCoordinator`、`AppRouteBus`、`PetHUDBridge` 等 |
| 浮层宿主 | `Core/Window/ExtensionOverlayController.swift` | 工作台窗口标题等 |

---

## 依赖注入

- **路由**：优先 `AppRouteBus`；`presentAgentSettingsTab(index:)` 的 `index` 为 **工作台 0…4**。
- **`AgentClient`**：`@Environment(\.desktopPetAgentClient)`。
- **Store**：按需 `@EnvironmentObject`；`CareOverlayView` 需 `AgentSettingsStore` 以展示「饲养互动」规则状态（由 `AppCoordinator` 注入）。

---

## 页面结构（视觉）

- 表单：`Form` + `.formStyle(.grouped)`；`Section` 配说明 footer。
- **对话 / 自动化** 分区为纵向组合多个子 `Form`，外层 `ScrollView`（见 `ConversationCenterTabView`、`AutomationCenterTabView`）。

---

## 交互与反馈

- 破坏性操作：`role: .destructive` + 确认对话框。
- 钥匙串 / Token：行内 `caption` 反馈。
- 键盘模式、截屏：Alert 与自动化分区内隐私文案一致。

---

## 命名速查

| 类型 | 名称 |
|------|------|
| 工作台枚举 | `AgentSettingsWorkspaceTab` |
| 路由总线 | `AppRouteBus` |
| 宠窗快捷转发 | `PetHUDBridge` |
| 薄路由封装 | `DesktopPetAppRouter` |
| 浮层协议 | `OverlayPresenting` |

---

## 任务 → 入口（可发现性）

| 用户任务 | 推荐入口 |
|----------|----------|
| 调模型 / Key | 工作台 **连接**；菜单「打开智能体工作台…」 |
| 会话频道、旁白历史、人格 | 工作台 **对话**；对话面板工具栏 **时钟**按钮 |
| 喂食冷却、成长统计 | 工作台 **陪伴**；饲养面板 **成长与冷却…** |
| 触发器、隐私总开关 | 工作台 **自动化**；饲养面板 **旁白与自动化…** |
| Slack、盯屏 | 工作台 **集成** |
| 穿透、巡逻、缩放 | **系统设置**（DesktopPet 设置） |
| 不便找菜单 | 宠窗左下角 **⋯** |

---

## 回归清单

- 菜单分组与「打开智能体工作台」「截屏并旁白」。
- 宠窗 ⋯：对话、饲养、工作台、系统设置。
- 工作台五分区内容与滚动；旧通知深链是否落到正确分区。
- 聊天、触发器、Slack、盯屏、饲养旁白、无障碍重检。

---

## 与历史重构阶段的对应

| 阶段 | 落点 |
|------|------|
| 路由 + Overlay | `DesktopPetAppRouter`、`ExtensionOverlayController`、`AppCoordinator` |
| Tab 代码拆分 | `AgentSettings/` 子文件 |
| 信息架构五分区 | `AgentSettingsView`、`AgentSettingsWorkspaceTab`、组合 Tab 视图 |
| 类型化路由 | `AppRouteBus`、通知桥接 |
| 文档 | 本文档 |
