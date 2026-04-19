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
    /// 在矩形内比较左 1/5 与右 1/5 平均亮度；`|Δ| <= deltaThreshold` 且本次启用任务期间曾出现过足够大的 `|Δ|` 时认为「够均匀」类完成态（Runner 维护武装状态）。`deltaThreshold` 为允许的最大亮度差（0…1）。
    case progressBarFilled(rect: NormalizedRect, deltaThreshold: Double)
}

/// 盯屏任务创建来源（持久化）。
enum ScreenWatchTaskCreationSource: String, Codable, Equatable {
    /// 用户在「连接」或盯屏相关界面里手动创建/编辑。
    case userManual = "userManual"
    /// 猫猫在 Slack 根据用户话自动创建。
    case slackAutomated = "slackAutomated"
}

/// 盯屏命中后气泡旁白的生成策略（`AppCoordinator.notifyScreenWatchHit`）。
enum ScreenWatchHitNarrativeKind: Equatable {
    /// 本地 OCR / 进度条启发式命中；旁白优先走模型，失败再用柔和兜底。
    case localHeuristic
    /// 模型 YES/NO 兜底命中；气泡仍用事件里的技术摘要。
    case visionFallback
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
    /// 命中并旁白后是否保持启用，以便再次盯同一条件（需配合 `repeatCooldownSeconds` 防抖）。
    var repeatAfterHit: Bool
    /// 可重复模式下，两次命中之间的最短间隔（秒），钳在 5…86400。
    var repeatCooldownSeconds: Double
    var creationSource: ScreenWatchTaskCreationSource
    /// Slack 命中报告：`chat.postMessage` 的 `channel`；仅 `slackAutomated` 使用。
    var slackReportChannelId: String?
    /// Slack 命中报告：可选 `thread_ts`（挂在用户原话下）。
    var slackReportThreadTs: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, isEnabled, sampleIntervalSeconds, conditions
        case useVisionFallback, visionUserHint, visionFallbackCooldownSeconds
        case repeatAfterHit, repeatCooldownSeconds, createdAt
        case creationSource, slackReportChannelId, slackReportThreadTs
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
        repeatAfterHit: Bool = false,
        repeatCooldownSeconds: Double = 60,
        creationSource: ScreenWatchTaskCreationSource = .userManual,
        slackReportChannelId: String? = nil,
        slackReportThreadTs: String? = nil,
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
        self.repeatAfterHit = repeatAfterHit
        self.repeatCooldownSeconds = Self.clampRepeatCooldownSeconds(repeatCooldownSeconds)
        self.creationSource = creationSource
        self.slackReportChannelId = slackReportChannelId
        self.slackReportThreadTs = slackReportThreadTs
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
        let rawVision = try c.decodeIfPresent(Double.self, forKey: .visionFallbackCooldownSeconds) ?? 15
        visionFallbackCooldownSeconds = Self.clampVisionCooldownSeconds(rawVision)
        repeatAfterHit = try c.decodeIfPresent(Bool.self, forKey: .repeatAfterHit) ?? false
        let rawRepeat = try c.decodeIfPresent(Double.self, forKey: .repeatCooldownSeconds) ?? 60
        repeatCooldownSeconds = Self.clampRepeatCooldownSeconds(rawRepeat)
        creationSource = try c.decodeIfPresent(ScreenWatchTaskCreationSource.self, forKey: .creationSource) ?? .userManual
        slackReportChannelId = try c.decodeIfPresent(String.self, forKey: .slackReportChannelId)
        slackReportThreadTs = try c.decodeIfPresent(String.self, forKey: .slackReportThreadTs)
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
        try c.encode(repeatAfterHit, forKey: .repeatAfterHit)
        try c.encode(repeatCooldownSeconds, forKey: .repeatCooldownSeconds)
        try c.encode(creationSource, forKey: .creationSource)
        try c.encodeIfPresent(slackReportChannelId, forKey: .slackReportChannelId)
        try c.encodeIfPresent(slackReportThreadTs, forKey: .slackReportThreadTs)
        try c.encode(createdAt, forKey: .createdAt)
    }

    private static func clampVisionCooldownSeconds(_ raw: Double) -> Double {
        if raw.isNaN || raw.isInfinite { return 15 }
        return min(86_400, max(1, raw))
    }

    private static func clampRepeatCooldownSeconds(_ raw: Double) -> Double {
        if raw.isNaN || raw.isInfinite { return 60 }
        return min(86_400, max(5, raw))
    }
}

// MARK: - 盯屏表单辅助（编辑/新建共用）

extension ScreenWatchTask {
    /// 从条件列表取出首个 OCR 子串；无则空字符串。
    var firstOCRSubstring: String {
        for c in conditions {
            if case let .ocrContains(text, _) = c { return text }
        }
        return ""
    }

    /// 首个进度条条件（矩形 + 阈值）；无则 `nil`。
    var firstProgressBarCondition: (rect: NormalizedRect, deltaThreshold: Double)? {
        for c in conditions {
            if case let .progressBarFilled(rect, deltaThreshold) = c {
                return (rect, deltaThreshold)
            }
        }
        return nil
    }

    /// 与新建表单一致：先 OCR（若有），再进度条（若有）。
    static func buildConditions(ocrText: String, progressRect: NormalizedRect?, progressDelta: Double) -> [ScreenWatchCondition] {
        var out: [ScreenWatchCondition] = []
        let ocr = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ocr.isEmpty {
            out.append(.ocrContains(text: ocr, caseInsensitive: true))
        }
        if let r = progressRect {
            out.append(.progressBarFilled(rect: r, deltaThreshold: progressDelta))
        }
        return out
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
