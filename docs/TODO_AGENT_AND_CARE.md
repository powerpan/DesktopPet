# 饲养 · 智能体 · 叠加 UI（独立规划清单）

> 与 `docs/TODO.md` 主工程进度**分列**；实现时可再拆 issue / 里程碑。  
> 目标：在**现有桌宠窗口**上叠加一层（或多层）功能界面，**默认不占主卡片**，通过**菜单栏**统一「显示 / 隐藏」；不替代当前桌镜，而是扩展陪伴与互动。

## 实现状态摘要（与源码对齐）

| 区域 | 主要类型 / 路径 |
|------|-----------------|
| 编排 | `AppCoordinator`：注入 `PetCareModel`、`AgentSettingsStore`、`AgentSessionStore`、`AgentClient`、`AgentTriggerEngine`、`FrontmostAppWatcher`、`ExtensionOverlayController`；键鼠活动转发至触发引擎；宠窗移动/缩放时 `repositionIfNeeded`。 |
| 叠加窗口 | `ExtensionOverlayController`：`NSPanel` 饲养/聊天 + `NSWindow` 智能体设置。 |
| 饲养 | `Core/Care/PetCareState.swift`、`PetCareModel.swift`；UI `Features/Overlay/CareOverlayView.swift`。 |
| 智能体 | `Core/Agent/*`；UI `ChatOverlayView.swift`、`AgentSettingsView.swift`。 |

里程碑 M1～M5 中，**截屏多模态**与**流式 SSE** 仍为后续项；其余 MVP 已在主分支落地（见下文勾选）。

---

## 1. 总体原则

| 原则 | 说明 |
|------|------|
| 叠加而非换页 | 新功能以 `NSPanel`/`NSHostingView` 叠加层或 SwiftUI `overlay` + 独立窗口片段实现，与 `PetSpriteView` 桌镜区可并存、可折叠。 |
| 菜单栏总闸 | 单一入口：「显示饲养与互动面板」「显示智能体设置」等；隐藏时释放焦点、可选降低采样频率。 |
| 隐私与权限 | API Key、对话内容走 **Keychain / 本地**；截屏、辅助功能等**按需申请**，在设置里写清用途与开关。 |
| 可降级 | 无 Key、无网络、无权限时，饲养可做离线简化；智能体可提示「未配置」而非崩溃。 |

---

## 2. 猫猫饲养与互动（设计草案）

### 2.1 定位

- **轻量、偏情绪价值**：不做重度数值养成游戏；以「今日陪伴时长、简单心情、小奖励」为主，降低每日负担。
- **与桌镜联动（可选）**：例如「今日按键镜像累计 N 分钟」转化为少量好感；**可开关**，避免强迫用户为数值而开镜像。

### 2.2 核心概念（建议）

- **心情 / 能量**：二轴或合一（如 `calm` / `playful` / `sleepy`），由「用户是否常互动、是否长时间忽略、是否触发智能体」缓慢漂移，**日级衰减**即可。
- **喂食 / 道具**：极简——每日 1～3 次「点心」按钮 + 冷却；或仅「戳一戳」互动加心情，无复杂背包。
- **成就 / 戳章**：可选里程碑（连续打开应用 7 天、第一次完成智能体对话等），仅展示徽章条，不做排行榜。

### 2.3 界面（叠加层）

- **饲养面板**：小卡片或底部抽屉（高度可控），含：心情条、今日陪伴、一键互动、设置入口（与智能体设置可合并为「扩展设置」Tab）。
- **与主窗口关系**：`PetWindowController` 或新 `OverlayWindowController` 管理 `frame` 与 `level`，**跟随主宠窗口移动/缩放**（或锚定在宠窗一侧），菜单栏「隐藏」时 `orderOut` 或 `alpha=0` + 停止动画。

### 2.4 数据

- `UserDefaults` 或轻量 **SwiftData / JSON** 存：上次互动时间、心情快照、冷却时间戳；**不**存敏感对话（对话归智能体模块）。

### 2.5 待办（饲养）

- [x] 数据模型：`PetCareState`（心情、能量、上次喂食时间、累计陪伴秒等）。
- [x] 叠加 UI：SwiftUI 视图 + 与 `PetWindow` 布局约束/锚点策略。
- [x] 菜单栏：`NSMenu` 项「显示/隐藏饲养面板」+ 与 `AppCoordinator` 联动。
- [ ]（可选）与 `DeskMirrorModel` 暴露的「今日镜像活跃时长」挂钩，仅增量、可关。

---

## 3. 智能体对话（OpenAI 兼容后端与设定）

### 3.1 能力范围

- **后端**：HTTP(S) 调用 **OpenAI Chat Completions 兼容** API（`POST …/v1/chat/completions`）；在设置中可选 **当前服务商**（DeepSeek、通义千问 DashScope **兼容模式**、自定义），每套独立 **Base URL、模型 id、钥匙串 Key**（`KeychainStore` 分账户；旧版单一 Key 仍可读作 DeepSeek）。
- **设定**：独立「系统提示词 / 猫格设定」编辑器（多预设 + 自定义）；可选「用户昵称」「禁止话题」等短字段。
- **上下文**：滑动窗口条数 / Token 上限；**可选**「是否附带当前键盘摘要」——默认关闭，避免隐私风险。

### 3.2 安全

- API Key：**Keychain**（`kSecClassGenericPassword`；新版按服务商 `rawValue` 分账户，与 `AgentAPIProvider` 对齐）。
- 传输：TLS；日志中**脱敏**请求体。
- 退出应用或隐藏面板时：可选清空内存中的最近一轮 user 消息（配置项）。

### 3.3 待办（对话核心）

- [x] `AgentClient`：`URLSession` + 流式（SSE）或整段 JSON 解析二选一，先做整段 MVP。
- [x] `AgentSessionStore`：对话列表、system prompt 版本号、错误重试与超时。
- [x] UI：气泡列表 + 输入框 +「发送」；叠加在宠窗或独立窄条窗口。
- [ ] 流式 SSE、重试按钮与更细的会话历史策略（可选）。

---

## 4. 智能体触发与「多样化条件」（菜单栏 · 智能体设置）

在菜单栏增加 **「智能体设置…」**（或并入「扩展设置」窗口，多 Tab），建议 Tab 结构：

| Tab | 内容 |
|-----|------|
| 连接 | Base URL、API Key（Keychain）、Model、超时、代理（可选）。 |
| 人格 | 系统提示词、预设猫格、温度 / max_tokens（若 API 支持）。 |
| 触发器 | 多类型触发器列表（见下）；每项可启用、排序、冷却时间。 |
| 隐私 | 是否允许附带键入摘要、是否允许截屏分析、数据保留说明。 |

### 4.1 触发器类型（分阶段实现）

| 类型 | 说明 | 依赖 |
|------|------|------|
| **定时** | Cron 式或「每 N 分钟」一次；仅在前台或宠窗可见时触发（可配）。 | `Timer` / `DispatchSourceTimer` |
| **随机空闲** | 用户无键鼠输入超过 T 秒后，以概率 P 触发一句短问候。 | 已有输入采样可复用 |
| **键盘模式** | 检测到连续键序列或正则（如特定词后回车）；**慎用**，需明显提示与开关。 | 辅助功能 + 已有 `GlobalInputMonitor` |
| **屏幕 / 情境** | 定时或手动截屏 → 图像送多模态 API（若 DeepSeek 路线支持图）；否则先做「窗口标题 / 前台 App 名」文本触发。 | **Screen Recording** 或 `CGWindowList`；多模态则 API 能力 |

建议 **MVP 顺序**：定时 + 随机空闲 → 键盘关键字（简单）→ 前台应用名变化 → 最后再上截屏 + 视觉模型（权限与成本最高）。

### 4.2 触发器数据结构（建议）

```text
Trigger: id, enabled, kind(enum), cooldownSeconds, lastFiredAt, configJSON
  e.g. timer: { intervalMinutes, onlyWhenPetVisible }
  e.g. randomIdle: { idleSeconds, probability }
  e.g. keyboardPattern: { pattern, caseInsensitive }
  e.g. screen: { mode: interval | manual, maxWidth, blurFaces: bool }  // 后期
```

- 持久化：`UserDefaults` + Codable 或 SwiftData。
- 执行：`AgentTriggerEngine` 订阅各数据源，统一防抖后调用 `AgentClient`。

### 4.3 待办（设置与触发）

- [x] 菜单栏入口 + `NSWindow`/`Settings` 风格面板（或 SwiftUI `Settings` scene 扩展）。
- [x] Keychain 读写封装 + 设置 UI 绑定。
- [x] `AgentTriggerEngine` + 定时器 + 与 `MouseTracker`/`GlobalInputMonitor` 的轻量订阅。
- [x] 键盘模式：配置校验、**默认关闭**、首次开启二次确认。
- [x] 「前台应用名」无截屏权限版（`FrontmostAppWatcher`）。
- [x] 截屏：`ScreenCaptureKit` 主显示器单次帧 → 缩放 JPEG → OpenAI 兼容多模态 `chat/completions`；隐私总开关 + 屏幕录制权限；规格见 [`docs/SCREEN_SNAP_TRIGGER_SPEC.md`](SCREEN_SNAP_TRIGGER_SPEC.md)。

---

## 5. 与主工程 `docs/TODO.md` 的关系

- **主 TODO**：拖窗动画、巡逻静默、测试等继续跟主线。
- **本文档**：饲养 + 智能体 + 叠加 UI + 菜单栏设置；**较大功能**，建议单独分支（如 `feature/agent-care`）分 PR 合并。

---

## 6. 建议里程碑（可选）

1. **M1**：叠加空壳面板 + 菜单栏显隐 + 本地占位文案。（已完成）  
2. **M2**：饲养状态模型 + 简单 UI + 持久化。（已完成）  
3. **M3**：DeepSeek 文本对话 MVP + Keychain + 基础设置页。（已完成）  
4. **M4**：定时 + 随机空闲触发器。（已完成）  
5. **M5**：键盘模式触发（安全流程）→ 前台应用名（已完成）→ **截屏/多模态**（已实现 ScreenCaptureKit + 多模态 API，见 4.3）。

---

## 7. 文档与合规

- [x] README 增加「扩展功能」小节链接到本文档。
- [ ] 用户可见：DeepSeek 使用条款、数据出境说明（若适用）、截屏与键位监听的双重同意文案（当前设置内已有简要风险提示，正式发版前可再补独立说明页）。

可在开始编码前将本节与产品负责人对齐后再动权限类能力。
