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

/// 「气泡测试」触发器可选的固定旁白长度。
enum TestBubbleSample: String, Codable, CaseIterable, Identifiable, Sendable {
    case short
    case long

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "短气泡（一小段）"
        case .long: return "长气泡（多行）"
        }
    }

    /// 固定测试文案，不请求大模型。
    var cannedText: String {
        switch self {
        case .short:
            return "【测试·短】喵～这是短猫猫气泡，用来检查云朵是否紧凑。点气泡可以继续聊天哦。"
        case .long:
            return """
            【测试·长】这是一段刻意写得很长的旁白，用来检查：第一，多行文字时底部笔画是否会被裁切；第二，在内容很多时滚动区域是否顺手；第三，圆角与底板边缘是否干净。

            七七猫伸个懒腰：主人若在看这段字，说明你在认真调试触发器，辛苦啦～建议再试着切换回短气泡对比手感。也可以多点几次「立即触发」，历史里会按「气泡测试」类型记下每次的固定文案。

            （结尾再凑一句：风吹窗帘沙沙响，桌面上的时钟悄悄走过几秒。）
            """
        }
    }
}

struct AgentTriggerRule: Identifiable, Equatable, Codable {
    var id: UUID
    var enabled: Bool
    var kind: AgentTriggerKind
    var cooldownSeconds: Double
    var lastFiredAt: Date?
    /// 定时：间隔分钟；随机空闲：空闲秒、概率 0...1；键盘：pattern 字符串；前台：应用名子串
    var timerIntervalMinutes: Int
    var randomIdleSeconds: Int
    var randomIdleProbability: Double
    var keyboardPattern: String
    var frontAppNameContains: String
    /// 仅 `bubbleTest` 使用：决定「立即触发」时的固定文案长度。
    var testBubbleSample: TestBubbleSample

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
        testBubbleSample: TestBubbleSample
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, kind, cooldownSeconds, lastFiredAt
        case timerIntervalMinutes, randomIdleSeconds, randomIdleProbability
        case keyboardPattern, frontAppNameContains
        case testBubbleSample
    }

    static func new(kind: AgentTriggerKind) -> AgentTriggerRule {
        AgentTriggerRule(
            id: UUID(),
            enabled: kind == .timer || kind == .randomIdle || kind == .bubbleTest,
            kind: kind,
            cooldownSeconds: 120,
            lastFiredAt: nil,
            timerIntervalMinutes: 45,
            randomIdleSeconds: 90,
            randomIdleProbability: 0.08,
            keyboardPattern: "",
            frontAppNameContains: "Xcode",
            testBubbleSample: .short
        )
    }
}
