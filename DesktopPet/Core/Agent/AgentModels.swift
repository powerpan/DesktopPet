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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .timer: return "定时"
        case .randomIdle: return "随机空闲"
        case .keyboardPattern: return "键盘模式"
        case .frontApp: return "前台应用"
        case .screenSnap: return "截屏（规划中）"
        }
    }
}

struct AgentTriggerRule: Identifiable, Codable, Equatable {
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

    static func new(kind: AgentTriggerKind) -> AgentTriggerRule {
        AgentTriggerRule(
            id: UUID(),
            enabled: kind == .timer || kind == .randomIdle,
            kind: kind,
            cooldownSeconds: 120,
            lastFiredAt: nil,
            timerIntervalMinutes: 45,
            randomIdleSeconds: 90,
            randomIdleProbability: 0.08,
            keyboardPattern: "",
            frontAppNameContains: "Xcode"
        )
    }
}
