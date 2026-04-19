# 截屏触发器 — 实现规格书（设计落地）

本文档将「截屏触发器」产品/技术计划稿落实为**工程规格**；主路径已在应用内实现（`ScreenCaptureService`、`AgentClient` 多模态、`AgentTriggerEngine` 截屏管线、设置 UI、菜单栏入口）。若行为与下文不一致，以代码为准并回写本节。

---

## 1. 需求冻结（P0）

### 1.1 最低系统版本

- 工程当前 **macOS Deployment Target**：**14.0**（见 `DesktopPet.xcodeproj` 中 `MACOSX_DEPLOYMENT_TARGET`）。
- 截屏实现路径以 **macOS 14+** 为硬前提选型；若未来降低系统版本，需重新评估 ScreenCaptureKit（SCK）可用 API 子集。

### 1.2 捕获技术：ScreenCaptureKit（SCK）

- **主路径**：使用 **ScreenCaptureKit** 获取显示器帧/快照（具体为 `SCStream` 单帧抓取或等价「一次性内容」API，以实施时 Apple 文档与 SDK 为准）。
- **权限**：依赖用户授予 **屏幕录制**（系统设置 → 隐私与安全性 → 屏幕录制）。未授权时**不得**轮询弹窗；规则评估应失败静默，可选单次日志。
- **备选（非首版）**：`CGWindowListCreateImage` 等旧路径仅作技术对照，不作为默认实现（弃用风险、权限与 HiDPI 行为需单独评审）。

### 1.3 Base URL、模型与「视觉」能力

- 应用侧 HTTP 形态为 **OpenAI 兼容** `POST …/v1/chat/completions`（见现有 `AgentClient`）。
- **供应商能力不可在仓库内写死**：官方文档首页示例当前以**纯文本** `messages` 为主；是否支持 **图像/多模态** 取决于用户在设置中填写的 **Base URL + model** 及该平台该模型的实际能力。
- **实施前必做核对**（发版 checklist）：
  1. 在对应平台（如 DeepSeek 控制台 / 文档 / 模型卡片）确认 **当前所选 `model` 是否支持 vision** 及请求体格式（通常为 `content: [{type:"text",...},{type:"image_url",...}]`）。
  2. 若不支持：必须走规格 **§3.3 降级策略**，禁止把 Base64 图静默丢弃后仍假装「已读屏」生成旁白。

### 1.4 默认间隔与冷却（建议默认值，编码时采用）

以下数值为**产品建议**，写入 `AgentTriggerRule` 的截屏专用字段或嵌套配置（结构体名实施时自定）：

| 参数 | 建议默认 | 说明 |
|------|-----------|------|
| `screenSnapIntervalMinutes` | **20** | 两次**成功发起**截屏旁白之间的最小间隔（与「定时器」语义对齐，独立字段避免与 `timerIntervalMinutes` 混用）。 |
| `cooldownSeconds`（规则级） | **900**（15 分钟） | 与引擎现有「冷却」一致：防止与间隔逻辑双重限制时取**更严者**或合并为一条策略（实施时二选一并在代码注释写清）。 |
| `onlyWhenPetVisible` | **true**（首版默认） | 与 `randomIdle` 使用 `isPetVisible()` 一致，降低会议投屏等场景误触。 |
| 空闲抽样（若做第二阶段） | `idleAtLeastSeconds` ≥ **120**，概率 ≤ **0.05** | 与现有随机空闲触发器风格一致，独立计数。 |

**策略说明**：首版推荐 **「定时间隔 + 仅宠物可见 + 较长冷却」**；`cooldownSeconds` 与 `screenSnapIntervalMinutes` 若同时存在，推荐引擎层统一为：`nextEligibleAt = max(lastFiredAt + cooldown, lastCaptureAttempt + interval)` 的伪代码语义，避免用户困惑（实施 PR 中写清）。

---

## 2. AgentClient / API 契约（P1）

### 2.1 现状

- `completeChat(..., messages: [[String: String]], ...)` 仅支持 `role` + 字符串 `content`，无法满足多模态。

### 2.2 目标 JSON 形态（与 OpenAI Chat Completions 对齐）

`messages` 中每条消息：

- **纯文本（保持兼容）**：`{ "role": "user", "content": "字符串" }`（现有行为）。
- **多模态（新增）**：`{ "role": "user", "content": [ ... ] }`，其中 `content` 为数组，元素形如：
  - `{ "type": "text", "text": "..." }`
  - `{ "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,..." } }`

**注意**：部分供应商支持 `detail: low|high|auto` 字段，实施时作为可选参数透传；未支持则应剥离以免 400。

### 2.3 Swift 侧建模建议（规格，非强制命名）

- 引入 `ChatMessage` / `ChatContentPart` 枚举（`text(String)`、`imageData(mime: Data)` 或 `imageBase64URL(String)`），由统一 builder 序列化为 JSON。
- `AgentClient` 保留一条 **纯文本便捷重载**（内部转为单段 `text`），保证现有调用方零改动或最小改动。

### 2.4 错误与回退

- HTTP 4xx 且 body 提示 `content` / `image` 不支持：应标记为「本模型不支持视觉」，UI 可提示用户改用支持 vision 的 model 或关闭截屏触发。
- 超时：沿用现有 `URLSession` 超时策略；截屏类请求体积大，可适当上调 `timeoutIntervalForRequest`（仅对含图请求或全局策略二选一）。

---

## 3. ScreenCaptureService 模块规格（P2）

### 3.1 职责边界

单类型或 `actor` / `@MainActor` 服务，**仅**负责：

1. 查询/监听屏幕录制授权状态（只读 + 引导用户打开系统设置，不在此模块弹业务 Alert）。
2. 在已授权时执行 **单次**捕获，返回 `Result<CapturedFrame, CaptureError>`。
3. 输出 **内存中** 的压缩位图（`Data` + MIME），默认 **不写磁盘**。

**不负责**：拼装 prompt、调用 `AgentClient`、更新 `lastFiredAt`（归引擎）。

### 3.2 显示器范围

- **首版**：默认 **主显示器**（菜单栏所在屏或 `NSScreen.main` 对应逻辑）；配置项预留 `captureTarget: main | allDisplays`（`allDisplays` 可为 Phase 2：拼接或只取主屏以外第一张）。
- 多屏拼接属于**非目标**或二期（带宽与隐私风险更高）。

### 3.3 图像管道（固定顺序）

1. 从 SCK 取得原始像素缓冲（格式依 API）。
2. 缩放到 **最大边 ≤ 1024 px**（配置允许 768/1024 两档）；保持宽高比。
3. 编码为 **JPEG**，质量默认 **0.72**（可配置 0.55～0.85）；若未来支持 WebP 再扩展。
4. 组装 `data:image/jpeg;base64,...` URL 或仅返回 `Data` 由上层拼 URL（推荐上层拼，便于单元测试注入假图）。

### 3.4 错误类型（建议枚举）

- `permissionDenied` — 无屏幕录制权限。
- `captureFailed(reason: String)` — SCK 回调失败、无显示器等。
- `encodingFailed` — 压缩失败。
- `cancelled` — 用户关闭总开关或规则在异步捕获完成前被禁用（引擎应协作取消）。

### 3.5 安全与磁盘

- **默认**：捕获缓冲区与 JPEG `Data` 仅存在于内存，请求结束后释放；**禁止**写入 `UserDefaults`、旁白历史或日志文件。
- **调试**：仅 `#if DEBUG` 或隐藏「开发者」开关下允许写临时目录，且默认关闭。

---

## 4. AgentTriggerEngine 集成规格（P3）

### 4.1 闸门逻辑（AND）

一次自动截屏旁白尝试仅当：

1. `settings.screenSnapTriggerMasterEnabled == true`  
2. 规则 `rule.enabled == true` 且 `rule.kind == .screenSnap`  
3. `!session.isSending`（与现有触发一致，避免并发请求）  
4. 冷却与间隔满足（见 §1.4）  
5. 若配置 `onlyWhenPetVisible`：`isPetVisible() == true`  
6. 系统已授予屏幕录制权限（否则 `evaluateScreenSnap` 返回 false，不 bump `lastFiredAt`）

### 4.2 `tick` 内行为

- 在现有 `switch rule.kind` 分支中实现 `evaluateScreenSnap(rule, ctx) -> Bool`。
- **禁止**在 1s `Timer` 回调内同步执行重 CPU/SCK 阻塞；应：
  - `evaluateScreenSnap` 仅做轻量检查；若应触发，则 `Task { await captureAndFire(rule) }` 或专用串行队列，且用 `isSending`/「截屏任务进行中」标志防止重入。
- **成功定义**：图像已编码且 API 成功返回旁白文本并进入 `firePrologue` 成功路径后，才更新 `lastFiredAt`。

### 4.3 `forceFireTrigger`

- 移除或条件化当前对 `screenSnap` 的硬 `return`：当总开关开且已授权时，允许「立即触发」走 **单次捕获 + 多模态请求**；失败时向 UI 返回错误（不伪造成功旁白）。
- 与设置页按钮 `disabled` 状态联动：未授权时可禁用按钮并提示打开系统设置。

### 4.4 占位符扩展

在 `firePrologue` 拼装 `extra` 或独立片段时增加（示例名）：

- `{screenCaptureMeta}`：ISO8601 时间、逻辑分辨率、目标显示器索引、`degradedToTextOnly: true/false`（见 §3.3 降级）。

系统提示中应强调：**模型仅可依据所提供的图像与元数据发言，不得臆测未提供内容**（与现有键盘/前台安全文案风格一致）。

### 4.5 路由条件

- **首版**：`routes` 可为单条 `.always`，由规则级间隔/冷却控频。
- **二期**：扩展 `TriggerRouteCondition`（例如与 `frontAppContains` 组合），或增加「黑名单 App 不截屏」子串列表（产品另定）。

---

## 5. 降级策略（模型不支持 vision 时）

**B（文本降级，推荐为 MVP- 过渡）**：不附图像；`{screenCaptureMeta}` 标记 `degradedToTextOnly`，`user` 内容仅包含：

- 当前前台应用本地化名称（已有 `FrontmostAppWatcher` / `NSWorkspace` 路径可复用）。
- 一句说明：「用户启用了截屏类旁白，但当前模型或端点不支持图像输入，以下为不含画面像素的安全摘要。」

**A（本地视觉，后期）**：使用 Apple Vision / OCR 生成简短中文描述再走纯文本模型 — **不纳入首版范围**，单独立项。

---

## 6. 隐私与 UI 文案草案（P4）

### 6.1 首次打开「截屏类触发（总开关）」Alert（标题 + 正文要点）

- **标题**：关于截屏类触发  
- **正文要点**（可分段显示）：
  1. 开启后，应用在满足你设置的间隔与条件时，可能截取 **显示器画面（默认主显示器）**，缩放并压缩后，通过你配置的 **API 地址** 发送至所选 **模型**，用于生成桌宠旁白。  
  2. 画面内容可能包含你屏幕上的 **任何可见信息**（文档、消息、浏览器等）。请在会议、投屏或敏感场景下 **关闭总开关** 或关闭对应规则。  
  3. 默认**不将截图文件保存到磁盘**；旁白历史仅保存**模型返回的文本**。若模型或端点不支持图像，应用可能仅发送**不含像素**的文字摘要（见 §5）。  
  4. 需在 **系统设置 → 隐私与安全性 → 屏幕录制** 中为 DesktopPet 授权；你可随时撤销授权或关闭本开关。  
- **按钮**：「暂不开启」 / 「我已了解并开启」

### 6.2 设置页「隐私」Tab / 触发器相关长说明要点

- 与键盘总闸并列说明：**截屏总闸关闭时，引擎不会对 `screenSnap` 规则做任何捕获或视觉请求**。  
- 链接或引导：打开系统设置的屏幕录制页（`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)` 等，实施时验证 URL 在目标 macOS 上有效）。  
- 提醒：更换 **Base URL / model** 后，视觉能力可能变化；异常时查看旁白失败提示。  
- 气泡展示旁白时可选副文案（小字）：「基于某时刻画面或文字摘要，非实时」— 产品可选。

### 6.3 合规清单（与 `docs/TODO_AGENT_AND_CARE.md` §7 对齐）

- 发版前：DeepSeek 使用条款、数据出境说明（若适用）、截屏与键位监听的双重同意 — 本文案为截屏侧草稿，需法务/产品最终审定。

---

## 7. 分阶段 PR 建议（与计划稿 §9 一致）

| 阶段 | 内容 |
|------|------|
| P1 | `AgentClient` 多模态 + 假图集成测试 |
| P2 | `ScreenCaptureService` + 权限检测 |
| P3 | `evaluateScreenSnap` + `forceFireTrigger` + 设置表单与默认 |
| P4 | 菜单栏「截屏旁白一次」、退避重试、文案与系统设置深链 |

---

## 8. 代码锚点（实施时改这些文件）

- [`DesktopPet/Core/Agent/AgentTriggerEngine.swift`](../DesktopPet/Core/Agent/AgentTriggerEngine.swift) — `tick` / `forceFireTrigger`  
- [`DesktopPet/Core/Agent/AgentClient.swift`](../DesktopPet/Core/Agent/AgentClient.swift) — 请求体  
- [`DesktopPet/Core/Agent/AgentModels.swift`](../DesktopPet/Core/Agent/AgentModels.swift) — `AgentTriggerRule` 扩展字段、可选 `TriggerRouteCondition`  
- [`DesktopPet/Core/Agent/AgentSettingsStore.swift`](../DesktopPet/Core/Agent/AgentSettingsStore.swift) — 总开关已存在  
- [`DesktopPet/Features/Overlay/AgentSettingsView.swift`](../DesktopPet/Features/Overlay/AgentSettingsView.swift) — UI、Alert、禁用逻辑  

---

*文档版本：与仓库内计划稿「截屏触发器设计」对应；后续以 PR 更新本节「文档版本」或 CHANGELOG。*
