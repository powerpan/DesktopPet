//
// AgentModels.swift
// 智能体消息、触发器类型与规则（Codable）。
//

import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

/// 用户与猫猫的一个对话频道（持久化）。
struct ChatChannel: Identifiable, Equatable, Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
}

/// 条件触发旁白历史条目（持久化）。
struct TriggerSpeechRecord: Identifiable, Equatable, Codable {
    var id: UUID
    /// 模型返回的旁白正文（气泡与续聊上下文）。
    var text: String
    var triggerKind: AgentTriggerKind
    var createdAt: Date
    /// 本次请求中发给模型的 user 消息全文（占位符已替换）；无 user 上下文时为 nil。
    var userPromptSent: String?
    /// 与本次请求一并发送的截图在 Application Support 中的文件名（`\<id\>.jpg`）；无图时为 nil。
    var userRequestSnapshotFileName: String?

    init(
        id: UUID = UUID(),
        text: String,
        triggerKind: AgentTriggerKind,
        createdAt: Date = Date(),
        userPromptSent: String? = nil,
        userRequestSnapshotFileName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.triggerKind = triggerKind
        self.createdAt = createdAt
        self.userPromptSent = userPromptSent
        self.userRequestSnapshotFileName = userRequestSnapshotFileName
    }
}

/// 触发成功后交给 UI / 历史记录的一包数据。
struct TriggerSpeechPayload {
    var text: String
    var triggerKind: AgentTriggerKind
    /// 已渲染占位符、即将作为 user 发给模型的内容；无模型调用时可为 nil。
    var userPrompt: String?
    /// 截屏旁白：与 API 请求使用的同一张 JPEG（写入 Application Support 后再记入历史）。
    var requestSnapshotJPEG: Data?
}

enum AgentTriggerKind: String, CaseIterable, Identifiable, Codable {
    case timer
    case randomIdle
    case keyboardPattern
    case frontApp
    case screenSnap
    /// 饲养面板「喂食 / 戳戳」成功时请求旁白（不走定时 tick；由应用发通知触发）。
    case careInteraction

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .timer: return "定时"
        case .randomIdle: return "随机空闲"
        case .keyboardPattern: return "键盘模式"
        case .frontApp: return "前台应用"
        case .screenSnap: return "截屏"
        case .careInteraction: return "饲养互动"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        if s == "bubbleTest" {
            self = .randomIdle
            return
        }
        guard let v = AgentTriggerKind(rawValue: s) else {
            self = .timer
            return
        }
        self = v
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// 单条旁白请求分支内的匹配条件（同一路由内为 AND）。
enum TriggerRouteCondition: Equatable, Codable, Sendable {
    /// 恒为真，用于兜底分支。
    case always
    /// 最近按键缓冲中包含子串（大小写敏感，与旧版键盘触发一致）。
    case keyboardContains(String)
    /// 当前前台本地化名称包含子串（大小写不敏感）。
    case frontAppContains(String)
    /// 自上次系统记录的键鼠活动起的空闲秒数阈值。
    case idleAtLeastSeconds(Int)
    /// 相对 `lastFiredAt` 至少经过的分钟数（可与规则级定时间隔并用作额外 tightening）。
    case timerElapsedAtLeastMinutes(Int)
}

/// 一条「条件 → 模型请求提示」旁白路由：优先级数值越大越优先；同.tick 内选第一条完全匹配的。
struct TriggerPromptRoute: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var enabled: Bool
    /// 越大越优先。
    var priority: Int
    var conditions: [TriggerRouteCondition]
    /// 用户向模型发送的 user 内容模板；可含 `{extra}`、`{triggerKind}`。
    var promptTemplate: String

    init(
        id: UUID = UUID(),
        enabled: Bool = true,
        priority: Int = 0,
        conditions: [TriggerRouteCondition],
        promptTemplate: String
    ) {
        self.id = id
        self.enabled = enabled
        self.priority = priority
        self.conditions = conditions
        self.promptTemplate = promptTemplate
    }
}

struct AgentTriggerRule: Identifiable, Equatable, Codable {
    /// 与 `firePrologue` 历史行为一致的通用回退 user 模板（含 `{extra}` 占位）。
    static let standardPrologueTemplate = "请用一两句简体中文，像桌宠一样对用户说点什么。{extra}"

    /// 无路由命中、或磁盘上未保存默认模板时的「按触发器类型」默认 user 文案（可含 `{extra}`、`{triggerKind}`、`{matchedCondition}`、`{keySummary}`）。
    static func defaultPromptTemplate(for kind: AgentTriggerKind) -> String {
        switch kind {
        case .timer:
            return """
            定时铃响了，又到了可以陪用户说一句话的片刻。{extra}
            请用一两句简体中文，像桌宠一样轻松问好：可以好奇 Ta 刚刚在忙什么、要不要喝水或伸懒腰，不要写列表或长篇。
            """
        case .randomIdle:
            return """
            用户已经安静了一阵，也许离开键盘或在发呆。{extra}
            请用一两句简体中文，像桌宠一样温柔搭话：轻声问要不要休息一下、看看远处或活动肩颈，语气俏皮不写小作文。
            """
        case .keyboardPattern:
            return """
            这是「键盘模式」触发的旁白请求；若没有更细的路由命中，说明只走了基础匹配。{extra}
            请用一两句简体中文像桌宠一样接话：若内容可能涉及密码或隐私，要温和提醒保护好自己、避免泄露；否则可爱随聊即可。
            """
        case .frontApp:
            return """
            用户刚刚切换了前台应用。{extra}
            请用一两句简体中文，像桌宠一样对「正在用哪类软件」开个轻松玩笑或祝 Ta 专注愉快，不要捏造具体窗口内容或敏感数据。触发类型：{triggerKind}
            """
        case .screenSnap:
            return """
            用户已启用「截屏旁白」：若请求中附带主显示器截图，请仅依据截图与下文元数据用一两句简体中文像桌宠一样轻松点评或关心用户状态；不要复述敏感信息、不要编造截图中不存在的细节。若未附带图像（例如模型不支持视觉、已降级为文字摘要），请诚实以桌宠口吻闲聊，勿假装已看到像素画面。
            画面元数据：{screenCaptureMeta}
            {extra}
            """
        case .careInteraction:
            return """
            用户刚在饲养面板完成了一次互动，以下为应用整理的数值与操作摘要（含在 {careContext}）。
            请用一两句简体中文，以桌宠口吻给出**动作反馈**（开心、呼噜、蹭手、撒娇等小描写均可），不要像报表一样复读数字列表。{extra}
            """
        }
    }

    /// 用户点击「添加旁白路由」时，新路由 `promptTemplate` 的初值（偏「本条条件命中」场景，仍支持占位符）。
    static func newRoutePromptTemplate(for kind: AgentTriggerKind) -> String {
        switch kind {
        case .timer:
            return """
            本条路由条件满足时，定时间隔已到。{extra}
            请用一两句简体中文像桌宠一样问候用户；可结合「定时」开个小玩笑，不要冗长。
            """
        case .randomIdle:
            return """
            本条路由条件满足时，用户已空闲足够久。{extra}
            请用一两句简体中文像桌宠一样轻声闲聊，鼓励适当放松，语气暖。
            """
        case .keyboardPattern:
            return """
            本条键盘旁白路由已命中。条件概要：{matchedCondition}。{extra}
            请用一两句简体中文像桌宠一样接话；若与密码、账号或隐私相关，请温柔提醒防泄露与截图风险，不要说教。
            """
        case .frontApp:
            return """
            本条前台旁白路由已命中。条件概要：{matchedCondition}。{extra}
            请用一两句简体中文像桌宠一样对用户刚切到的应用氛围随口调侃或加油，不编造应用内隐私细节。
            """
        case .screenSnap:
            return """
            本条截屏旁白路由已命中。条件概要：{matchedCondition}。画面元数据：{screenCaptureMeta}。{extra}
            请用一两句简体中文像桌宠一样回应；有图时紧扣画面氛围，无图时不要假装已见屏。
            """
        case .careInteraction:
            return """
            本条为饲养互动旁白路由。摘要：{careContext}；条件概要：{matchedCondition}。{extra}
            请用一两句简体中文像桌宠一样对刚才的互动做出可爱反馈，不要机械罗列数字。
            """
        }
    }

    var id: UUID
    var enabled: Bool
    var kind: AgentTriggerKind
    var cooldownSeconds: Double
    var lastFiredAt: Date?
    /// 定时：间隔分钟；随机空闲：空闲秒、概率 0...1；键盘：pattern 字符串；前台：应用名子串
    var timerIntervalMinutes: Int
    var randomIdleSeconds: Int
    var randomIdleProbability: Double
    /// 旧版单条件：当 `routes` 为空时由引擎回退使用；新配置应写入 `routes`。
    var keyboardPattern: String
    var frontAppNameContains: String
    /// 旁白请求分支：同 tick 内按 `priority` 选第一条全部条件满足的；空则回退旧字段逻辑。
    var routes: [TriggerPromptRoute]
    /// 无路由命中时使用的 user 模板（可为空，引擎再回退到 `standardPrologueTemplate`）。
    var defaultPromptTemplate: String
    /// 本条旁白请求专用温度；`nil` 表示使用 `AgentSettingsStore.triggerDefaultTemperature`。
    var triggerTemperature: Double?
    /// 本条旁白请求的 `max_tokens`；`nil` 表示使用 `AgentSettingsStore.triggerDefaultMaxTokens`。
    var triggerMaxTokens: Int?
    // MARK: 截屏专用（其它 kind 忽略；持久化兼容旧 JSON）
    /// 两次成功截屏旁白之间的最小间隔（分钟）；与 `cooldownSeconds` 取更长者生效。
    var screenSnapIntervalMinutes: Int
    /// 仅宠物窗口可见时才允许自动截屏旁白。
    var screenSnapOnlyWhenPetVisible: Bool
    /// 截图长边缩放上限（768 或 1024）。
    var screenSnapMaxEdgePixels: Int
    /// JPEG 压缩系数 0.55...0.85
    var screenSnapJPEGQuality: Double

    init(
        id: UUID,
        enabled: Bool,
        kind: AgentTriggerKind,
        cooldownSeconds: Double,
        lastFiredAt: Date?,
        timerIntervalMinutes: Int,
        randomIdleSeconds: Int,
        randomIdleProbability: Double,
        keyboardPattern: String,
        frontAppNameContains: String,
        routes: [TriggerPromptRoute],
        defaultPromptTemplate: String,
        triggerTemperature: Double? = nil,
        triggerMaxTokens: Int? = nil,
        screenSnapIntervalMinutes: Int = 20,
        screenSnapOnlyWhenPetVisible: Bool = true,
        screenSnapMaxEdgePixels: Int = 1024,
        screenSnapJPEGQuality: Double = 0.72
    ) {
        self.id = id
        self.enabled = enabled
        self.kind = kind
        self.cooldownSeconds = cooldownSeconds
        self.lastFiredAt = lastFiredAt
        self.timerIntervalMinutes = timerIntervalMinutes
        self.randomIdleSeconds = randomIdleSeconds
        self.randomIdleProbability = randomIdleProbability
        self.keyboardPattern = keyboardPattern
        self.frontAppNameContains = frontAppNameContains
        self.routes = routes
        self.defaultPromptTemplate = defaultPromptTemplate
        self.triggerTemperature = triggerTemperature
        self.triggerMaxTokens = triggerMaxTokens
        self.screenSnapIntervalMinutes = screenSnapIntervalMinutes
        self.screenSnapOnlyWhenPetVisible = screenSnapOnlyWhenPetVisible
        self.screenSnapMaxEdgePixels = screenSnapMaxEdgePixels
        self.screenSnapJPEGQuality = screenSnapJPEGQuality
    }

    /// 截屏规则：成功触发之间的最短等待（秒）= max(冷却, 定时间隔)。
    func screenSnapEffectiveMinIntervalSeconds() -> TimeInterval {
        max(cooldownSeconds, TimeInterval(screenSnapIntervalMinutes * 60))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        kind = try c.decode(AgentTriggerKind.self, forKey: .kind)
        cooldownSeconds = try c.decode(Double.self, forKey: .cooldownSeconds)
        lastFiredAt = try c.decodeIfPresent(Date.self, forKey: .lastFiredAt)
        timerIntervalMinutes = try c.decode(Int.self, forKey: .timerIntervalMinutes)
        randomIdleSeconds = try c.decode(Int.self, forKey: .randomIdleSeconds)
        randomIdleProbability = try c.decode(Double.self, forKey: .randomIdleProbability)
        keyboardPattern = try c.decode(String.self, forKey: .keyboardPattern)
        frontAppNameContains = try c.decode(String.self, forKey: .frontAppNameContains)
        var decodedRoutes = try c.decodeIfPresent([TriggerPromptRoute].self, forKey: .routes) ?? []
        var decodedDefault = try c.decodeIfPresent(String.self, forKey: .defaultPromptTemplate) ?? ""
        let migrated = Self.migrateLegacyRoutesIfNeeded(
            kind: kind,
            keyboardPattern: keyboardPattern,
            frontAppNameContains: frontAppNameContains,
            routes: decodedRoutes,
            defaultPromptTemplate: decodedDefault
        )
        routes = migrated.routes
        defaultPromptTemplate = migrated.defaultPromptTemplate
        triggerTemperature = try c.decodeIfPresent(Double.self, forKey: .triggerTemperature)
        triggerMaxTokens = try c.decodeIfPresent(Int.self, forKey: .triggerMaxTokens)
        screenSnapIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .screenSnapIntervalMinutes) ?? 20
        screenSnapOnlyWhenPetVisible = try c.decodeIfPresent(Bool.self, forKey: .screenSnapOnlyWhenPetVisible) ?? true
        screenSnapMaxEdgePixels = try c.decodeIfPresent(Int.self, forKey: .screenSnapMaxEdgePixels) ?? 1024
        screenSnapJPEGQuality = try c.decodeIfPresent(Double.self, forKey: .screenSnapJPEGQuality) ?? 0.72
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(kind, forKey: .kind)
        try c.encode(cooldownSeconds, forKey: .cooldownSeconds)
        try c.encodeIfPresent(lastFiredAt, forKey: .lastFiredAt)
        try c.encode(timerIntervalMinutes, forKey: .timerIntervalMinutes)
        try c.encode(randomIdleSeconds, forKey: .randomIdleSeconds)
        try c.encode(randomIdleProbability, forKey: .randomIdleProbability)
        try c.encode(keyboardPattern, forKey: .keyboardPattern)
        try c.encode(frontAppNameContains, forKey: .frontAppNameContains)
        try c.encode(routes, forKey: .routes)
        try c.encode(defaultPromptTemplate, forKey: .defaultPromptTemplate)
        try c.encodeIfPresent(triggerTemperature, forKey: .triggerTemperature)
        try c.encodeIfPresent(triggerMaxTokens, forKey: .triggerMaxTokens)
        try c.encode(screenSnapIntervalMinutes, forKey: .screenSnapIntervalMinutes)
        try c.encode(screenSnapOnlyWhenPetVisible, forKey: .screenSnapOnlyWhenPetVisible)
        try c.encode(screenSnapMaxEdgePixels, forKey: .screenSnapMaxEdgePixels)
        try c.encode(screenSnapJPEGQuality, forKey: .screenSnapJPEGQuality)
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, kind, cooldownSeconds, lastFiredAt
        case timerIntervalMinutes, randomIdleSeconds, randomIdleProbability
        case keyboardPattern, frontAppNameContains
        case routes, defaultPromptTemplate
        case triggerTemperature, triggerMaxTokens
        case screenSnapIntervalMinutes, screenSnapOnlyWhenPetVisible, screenSnapMaxEdgePixels, screenSnapJPEGQuality
    }

    /// 旧数据无 `routes` 时，从单字段生成等价路由，避免升级后行为突变。
    private static func migrateLegacyRoutesIfNeeded(
        kind: AgentTriggerKind,
        keyboardPattern: String,
        frontAppNameContains: String,
        routes: [TriggerPromptRoute],
        defaultPromptTemplate: String
    ) -> (routes: [TriggerPromptRoute], defaultPromptTemplate: String) {
        guard routes.isEmpty else {
            let def = defaultPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.defaultPromptTemplate(for: kind)
                : defaultPromptTemplate
            return (routes, def)
        }
        let def = defaultPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultPromptTemplate(for: kind)
            : defaultPromptTemplate
        switch kind {
        case .keyboardPattern:
            let p = keyboardPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty { return ([], def) }
            let route = TriggerPromptRoute(
                enabled: true,
                priority: 0,
                conditions: [.keyboardContains(p)],
                promptTemplate: def
            )
            return ([route], def)
        case .frontApp:
            let n = frontAppNameContains.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty {
                let route = TriggerPromptRoute(enabled: true, priority: 0, conditions: [.always], promptTemplate: def)
                return ([route], def)
            }
            let route = TriggerPromptRoute(
                enabled: true,
                priority: 0,
                conditions: [.frontAppContains(n)],
                promptTemplate: def
            )
            return ([route], def)
        case .timer, .randomIdle, .screenSnap, .careInteraction:
            let route = TriggerPromptRoute(enabled: true, priority: 0, conditions: [.always], promptTemplate: def)
            return ([route], def)
        }
    }

    static func new(kind: AgentTriggerKind) -> AgentTriggerRule {
        let def = Self.defaultPromptTemplate(for: kind)
        let routeTmpl = Self.newRoutePromptTemplate(for: kind)
        let defaultRoutes: [TriggerPromptRoute]
        let kbd: String
        let front: String
        switch kind {
        case .timer, .randomIdle, .screenSnap, .careInteraction:
            defaultRoutes = [TriggerPromptRoute(enabled: true, priority: 0, conditions: [.always], promptTemplate: routeTmpl)]
            kbd = ""
            front = ""
        case .keyboardPattern:
            defaultRoutes = []
            kbd = ""
            front = ""
        case .frontApp:
            kbd = ""
            front = "Xcode"
            defaultRoutes = [
                TriggerPromptRoute(enabled: true, priority: 0, conditions: [.frontAppContains("Xcode")], promptTemplate: routeTmpl),
            ]
        }
        let defaultEnabled = kind == .timer || kind == .randomIdle
        let defaultCooldown: Double = {
            if kind == .careInteraction { return 3 }
            if kind == .screenSnap { return 900 }
            return 120
        }()
        return AgentTriggerRule(
            id: UUID(),
            enabled: defaultEnabled,
            kind: kind,
            cooldownSeconds: defaultCooldown,
            lastFiredAt: nil,
            timerIntervalMinutes: 45,
            randomIdleSeconds: 90,
            randomIdleProbability: 0.08,
            keyboardPattern: kbd,
            frontAppNameContains: front,
            routes: defaultRoutes,
            defaultPromptTemplate: def,
            triggerTemperature: nil,
            triggerMaxTokens: nil,
            screenSnapIntervalMinutes: 20,
            screenSnapOnlyWhenPetVisible: true,
            screenSnapMaxEdgePixels: 1024,
            screenSnapJPEGQuality: 0.72
        )
    }
}
