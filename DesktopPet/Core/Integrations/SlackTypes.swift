//
// SlackTypes.swift
// Slack 集成：配置与频道绑定（UserDefaults + Codable）。
//

import CoreGraphics
import Foundation

// MARK: - Slack 集成配置

struct SlackIntegrationConfig: Codable, Equatable {
    var enabled: Bool = false
    /// 要轮询的 Slack 频道 ID（如 `C01234567`）。
    var monitoredChannelId: String = ""
    /// 轮询间隔（秒），建议 ≥ 3。
    var pollIntervalSeconds: Double = 5
    var syncInbound: Bool = true
    var syncOutbound: Bool = true
}

struct SlackChannelBinding: Codable, Equatable, Identifiable {
    var id: UUID
    /// Slack 频道或线程父级 `C…`（MVP 仅频道）。
    var slackChannelId: String
    var localChannelId: UUID
    var createdAt: Date

    init(id: UUID = UUID(), slackChannelId: String, localChannelId: UUID, createdAt: Date = Date()) {
        self.id = id
        self.slackChannelId = slackChannelId
        self.localChannelId = localChannelId
        self.createdAt = createdAt
    }
}

// MARK: - 盯屏任务

/// 归一化矩形（相对主屏 0…1，左上为原点）。
struct NormalizedRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum ScreenWatchCondition: Codable, Equatable {
    /// 主屏截图 OCR 后是否包含子串。
    case ocrContains(text: String, caseInsensitive: Bool)
    /// 在矩形内比较左 1/5 与右 1/5 平均亮度；`|Δ| <= deltaThreshold` 时认为「条已够均匀」类完成态（启发式）。`deltaThreshold` 为允许的最大亮度差（0…1）。
    case progressBarFilled(rect: NormalizedRect, deltaThreshold: Double)
}

struct ScreenWatchTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var isEnabled: Bool
    var sampleIntervalSeconds: Double
    /// 全部条件 AND 满足则命中。
    var conditions: [ScreenWatchCondition]
    var useVisionFallback: Bool
    /// 模型兜底时的用户说明（会随截图发给模型）。
    var visionUserHint: String
    /// 模型兜底（多模态）两次 `completeChat` 之间的最短间隔（秒），按任务配置；建议长任务设大一些。
    var visionFallbackCooldownSeconds: Double
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, isEnabled, sampleIntervalSeconds, conditions
        case useVisionFallback, visionUserHint, visionFallbackCooldownSeconds, createdAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        isEnabled: Bool = true,
        sampleIntervalSeconds: Double = 3,
        conditions: [ScreenWatchCondition] = [],
        useVisionFallback: Bool = false,
        visionUserHint: String = "",
        visionFallbackCooldownSeconds: Double = 15,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.conditions = conditions
        self.useVisionFallback = useVisionFallback
        self.visionUserHint = visionUserHint
        self.visionFallbackCooldownSeconds = Self.clampVisionCooldownSeconds(visionFallbackCooldownSeconds)
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        sampleIntervalSeconds = try c.decode(Double.self, forKey: .sampleIntervalSeconds)
        conditions = try c.decode([ScreenWatchCondition].self, forKey: .conditions)
        useVisionFallback = try c.decode(Bool.self, forKey: .useVisionFallback)
        visionUserHint = try c.decode(String.self, forKey: .visionUserHint)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        let raw = try c.decodeIfPresent(Double.self, forKey: .visionFallbackCooldownSeconds) ?? 15
        visionFallbackCooldownSeconds = Self.clampVisionCooldownSeconds(raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(sampleIntervalSeconds, forKey: .sampleIntervalSeconds)
        try c.encode(conditions, forKey: .conditions)
        try c.encode(useVisionFallback, forKey: .useVisionFallback)
        try c.encode(visionUserHint, forKey: .visionUserHint)
        try c.encode(visionFallbackCooldownSeconds, forKey: .visionFallbackCooldownSeconds)
        try c.encode(createdAt, forKey: .createdAt)
    }

    private static func clampVisionCooldownSeconds(_ raw: Double) -> Double {
        if raw.isNaN || raw.isInfinite { return 15 }
        return min(86_400, max(1, raw))
    }
}

enum ScreenWatchEventKind: String, Codable {
    case hit
    case error
    case disabled
}

struct ScreenWatchEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var taskId: UUID
    var taskTitle: String
    var kind: ScreenWatchEventKind
    var detail: String
    var createdAt: Date

    init(id: UUID = UUID(), taskId: UUID, taskTitle: String, kind: ScreenWatchEventKind, detail: String, createdAt: Date = Date()) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.kind = kind
        self.detail = detail
        self.createdAt = createdAt
    }
}
