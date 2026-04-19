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
    /// 在矩形区域内比较左右亮度差，大于阈值则认为「进度条已满」类状态（启发式，需用户把框选在进度条区域）。
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
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        isEnabled: Bool = true,
        sampleIntervalSeconds: Double = 3,
        conditions: [ScreenWatchCondition] = [],
        useVisionFallback: Bool = false,
        visionUserHint: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.conditions = conditions
        self.useVisionFallback = useVisionFallback
        self.visionUserHint = visionUserHint
        self.createdAt = createdAt
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
