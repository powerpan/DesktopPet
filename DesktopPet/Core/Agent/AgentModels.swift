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
    var text: String
    var triggerKind: AgentTriggerKind
    var createdAt: Date
}

/// 触发成功后交给 UI / 历史记录的一包数据。
struct TriggerSpeechPayload: Equatable {
    var text: String
    var triggerKind: AgentTriggerKind
}

enum AgentTriggerKind: String, Codable, CaseIterable, Identifiable {
    case timer
    case randomIdle
    case keyboardPattern
    case frontApp
    case screenSnap
    /// 不经过模型；在编辑页选短/长固定文案并点「立即触发」弹出旁白气泡（用于自测布局与流程）。
    case bubbleTest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .timer: return "定时"
        case .randomIdle: return "随机空闲"
        case .keyboardPattern: return "键盘模式"
        case .frontApp: return "前台应用"
        case .screenSnap: return "截屏（规划中）"
        case .bubbleTest: return "气泡测试"
        }
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

/// 「气泡测试」触发器可选的固定旁白长度。
enum TestBubbleSample: String, Codable, CaseIterable, Identifiable, Sendable {
    case short
    case long

    /// 短测试基准文案（长测试为其字符数的两倍，便于对比布局）。
    private static let shortTestLine = "【测试·短】喵～这是短猫猫气泡，用来检查云朵是否紧凑。点气泡可以继续聊天哦。"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "短气泡（一小段）"
        case .long: return "长气泡（短文本两倍长）"
        }
    }

    /// 固定测试文案，不请求大模型。
    var cannedText: String {
        switch self {
        case .short:
            return Self.shortTestLine
        case .long:
            return Self.shortTestLine + Self.shortTestLine
        }
    }
}

struct AgentTriggerRule: Identifiable, Equatable, Codable {
    /// 与 `firePrologue` 历史行为一致的默认 user 模板（含 `{extra}` 占位）。
    static let standardPrologueTemplate = "请用一两句简体中文，像桌宠一样对用户说点什么。{extra}"

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
    /// 仅 `bubbleTest` 使用：决定「立即触发」时的固定文案长度。
    var testBubbleSample: TestBubbleSample
    /// 旁白请求分支：同 tick 内按 `priority` 选第一条全部条件满足的；空则回退旧字段逻辑。
    var routes: [TriggerPromptRoute]
    /// 无路由命中时使用的 user 模板（可为空，引擎再回退到 `standardPrologueTemplate`）。
    var defaultPromptTemplate: String

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
        testBubbleSample: TestBubbleSample,
        routes: [TriggerPromptRoute],
        defaultPromptTemplate: String
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
        self.testBubbleSample = testBubbleSample
        self.routes = routes
        self.defaultPromptTemplate = defaultPromptTemplate
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
        testBubbleSample = try c.decodeIfPresent(TestBubbleSample.self, forKey: .testBubbleSample) ?? .short
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
        try c.encode(testBubbleSample, forKey: .testBubbleSample)
        try c.encode(routes, forKey: .routes)
        try c.encode(defaultPromptTemplate, forKey: .defaultPromptTemplate)
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, kind, cooldownSeconds, lastFiredAt
        case timerIntervalMinutes, randomIdleSeconds, randomIdleProbability
        case keyboardPattern, frontAppNameContains
        case testBubbleSample
        case routes, defaultPromptTemplate
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
                ? Self.standardPrologueTemplate
                : defaultPromptTemplate
            return (routes, def)
        }
        let def = defaultPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.standardPrologueTemplate
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
        case .timer, .randomIdle, .screenSnap:
            let route = TriggerPromptRoute(enabled: true, priority: 0, conditions: [.always], promptTemplate: def)
            return ([route], def)
        case .bubbleTest:
            return ([], def)
        }
    }

    static func new(kind: AgentTriggerKind) -> AgentTriggerRule {
        let std = Self.standardPrologueTemplate
        let defaultRoutes: [TriggerPromptRoute]
        let kbd: String
        let front: String
        switch kind {
        case .timer, .randomIdle, .screenSnap:
            defaultRoutes = [TriggerPromptRoute(enabled: true, priority: 0, conditions: [.always], promptTemplate: std)]
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
                TriggerPromptRoute(enabled: true, priority: 0, conditions: [.frontAppContains("Xcode")], promptTemplate: std),
            ]
        case .bubbleTest:
            defaultRoutes = []
            kbd = ""
            front = ""
        }
        return AgentTriggerRule(
            id: UUID(),
            enabled: kind == .timer || kind == .randomIdle || kind == .bubbleTest,
            kind: kind,
            cooldownSeconds: 120,
            lastFiredAt: nil,
            timerIntervalMinutes: 45,
            randomIdleSeconds: 90,
            randomIdleProbability: 0.08,
            keyboardPattern: kbd,
            frontAppNameContains: front,
            testBubbleSample: .short,
            routes: defaultRoutes,
            defaultPromptTemplate: std
        )
    }
}
