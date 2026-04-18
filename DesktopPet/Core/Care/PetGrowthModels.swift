//
// PetGrowthModels.swift
// 成长系统：配置、按日统计、衰减事件记录与统计聚合。
//

import Foundation

// MARK: - 配置（独立 UserDefaults，便于在设置页绑定）

struct PetGrowthConfig: Codable, Equatable {
    /// 每小时基础能量衰减（0...1 比例），例如 0.02 = 约 2%/小时
    var energyDrainPerHour: Double
    /// 每小时基础心情衰减
    var moodDrainPerHour: Double
    /// 每次「喂食」成功：心情增量（0~1 刻度）
    var feedMoodGain: Double
    /// 每次「喂食」成功：能量增量
    var feedEnergyGain: Double
    /// 每次「戳戳」成功：心情增量
    var petMoodGain: Double
    /// 每次「戳戳」成功：能量增量（默认可为 0，与旧行为一致）
    var petEnergyGain: Double
    /// 每小时是否尝试触发「随机成长事件」的概率权重 0...100（再乘以时段系数）
    var randomEventDensityPercent: Int
    /// 是否允许调用模型生成成长事件（失败则回退本地）
    var aiGrowthEventsEnabled: Bool
    /// 两次 AI 成长事件之间最少间隔（小时）
    var aiGrowthEventsMinIntervalHours: Double

    enum CodingKeys: String, CodingKey {
        case energyDrainPerHour
        case moodDrainPerHour
        case feedMoodGain
        case feedEnergyGain
        case petMoodGain
        case petEnergyGain
        case randomEventDensityPercent
        case aiGrowthEventsEnabled
        case aiGrowthEventsMinIntervalHours
    }

    init(
        energyDrainPerHour: Double,
        moodDrainPerHour: Double,
        feedMoodGain: Double,
        feedEnergyGain: Double,
        petMoodGain: Double,
        petEnergyGain: Double,
        randomEventDensityPercent: Int,
        aiGrowthEventsEnabled: Bool,
        aiGrowthEventsMinIntervalHours: Double
    ) {
        self.energyDrainPerHour = energyDrainPerHour
        self.moodDrainPerHour = moodDrainPerHour
        self.feedMoodGain = feedMoodGain
        self.feedEnergyGain = feedEnergyGain
        self.petMoodGain = petMoodGain
        self.petEnergyGain = petEnergyGain
        self.randomEventDensityPercent = randomEventDensityPercent
        self.aiGrowthEventsEnabled = aiGrowthEventsEnabled
        self.aiGrowthEventsMinIntervalHours = aiGrowthEventsMinIntervalHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        energyDrainPerHour = try c.decodeIfPresent(Double.self, forKey: .energyDrainPerHour) ?? Self.default.energyDrainPerHour
        moodDrainPerHour = try c.decodeIfPresent(Double.self, forKey: .moodDrainPerHour) ?? Self.default.moodDrainPerHour
        feedMoodGain = try c.decodeIfPresent(Double.self, forKey: .feedMoodGain) ?? Self.default.feedMoodGain
        feedEnergyGain = try c.decodeIfPresent(Double.self, forKey: .feedEnergyGain) ?? Self.default.feedEnergyGain
        petMoodGain = try c.decodeIfPresent(Double.self, forKey: .petMoodGain) ?? Self.default.petMoodGain
        petEnergyGain = try c.decodeIfPresent(Double.self, forKey: .petEnergyGain) ?? Self.default.petEnergyGain
        randomEventDensityPercent = try c.decodeIfPresent(Int.self, forKey: .randomEventDensityPercent) ?? Self.default.randomEventDensityPercent
        aiGrowthEventsEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiGrowthEventsEnabled) ?? Self.default.aiGrowthEventsEnabled
        aiGrowthEventsMinIntervalHours = try c.decodeIfPresent(Double.self, forKey: .aiGrowthEventsMinIntervalHours)
            ?? Self.default.aiGrowthEventsMinIntervalHours
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(energyDrainPerHour, forKey: .energyDrainPerHour)
        try c.encode(moodDrainPerHour, forKey: .moodDrainPerHour)
        try c.encode(feedMoodGain, forKey: .feedMoodGain)
        try c.encode(feedEnergyGain, forKey: .feedEnergyGain)
        try c.encode(petMoodGain, forKey: .petMoodGain)
        try c.encode(petEnergyGain, forKey: .petEnergyGain)
        try c.encode(randomEventDensityPercent, forKey: .randomEventDensityPercent)
        try c.encode(aiGrowthEventsEnabled, forKey: .aiGrowthEventsEnabled)
        try c.encode(aiGrowthEventsMinIntervalHours, forKey: .aiGrowthEventsMinIntervalHours)
    }

    static let `default` = PetGrowthConfig(
        energyDrainPerHour: 0.02,
        moodDrainPerHour: 0.012,
        feedMoodGain: 0.12,
        feedEnergyGain: 0.15,
        petMoodGain: 0.06,
        petEnergyGain: 0,
        randomEventDensityPercent: 35,
        aiGrowthEventsEnabled: false,
        aiGrowthEventsMinIntervalHours: 6
    )

    static func clamped(_ c: PetGrowthConfig) -> PetGrowthConfig {
        var o = c
        o.energyDrainPerHour = min(0.5, max(0, o.energyDrainPerHour))
        o.moodDrainPerHour = min(0.5, max(0, o.moodDrainPerHour))
        o.feedMoodGain = min(0.35, max(0, o.feedMoodGain))
        o.feedEnergyGain = min(0.35, max(0, o.feedEnergyGain))
        o.petMoodGain = min(0.35, max(0, o.petMoodGain))
        o.petEnergyGain = min(0.25, max(0, o.petEnergyGain))
        o.randomEventDensityPercent = min(100, max(0, o.randomEventDensityPercent))
        o.aiGrowthEventsMinIntervalHours = min(168, max(1, o.aiGrowthEventsMinIntervalHours))
        return o
    }
}

// MARK: - 按日统计（持久化在 PetCareState）

struct PetCompanionDayStats: Codable, Equatable, Identifiable {
    var dayKey: String
    /// 当日宠物窗口可见累计秒
    var companionSeconds: Int
    var feedCount: Int
    var petCount: Int
    var decayEventCount: Int

    var id: String { dayKey }

    static func empty(dayKey: String) -> PetCompanionDayStats {
        PetCompanionDayStats(dayKey: dayKey, companionSeconds: 0, feedCount: 0, petCount: 0, decayEventCount: 0)
    }
}

enum PetDecayEventSource: String, Codable, Equatable {
    case local
    case ai
}

struct PetDecayEventRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var occurredAt: Date
    var reasonCode: String
    var reasonText: String
    var moodDelta: Double
    var energyDelta: Double
    var source: PetDecayEventSource
    /// AI 原始回复截断保存，便于排错
    var rawModelResponse: String?

    static func make(
        reasonCode: String,
        reasonText: String,
        moodDelta: Double,
        energyDelta: Double,
        source: PetDecayEventSource,
        raw: String? = nil
    ) -> PetDecayEventRecord {
        PetDecayEventRecord(
            id: UUID(),
            occurredAt: Date(),
            reasonCode: reasonCode,
            reasonText: reasonText,
            moodDelta: moodDelta,
            energyDelta: energyDelta,
            source: source,
            rawModelResponse: raw.map { String($0.prefix(2000)) }
        )
    }
}

// MARK: - 统计聚合（只读）

struct PetGrowthMonthSummary: Equatable {
    var yearMonthKey: String
    var daysWithCompanion: Int
    var totalCompanionSeconds: Int
    var totalFeedCount: Int
    var totalPetCount: Int
    var totalDecayEvents: Int
    var bestStreakDaysWithCompanion: Int

    var averageCompanionMinutesPerActiveDay: Int {
        guard daysWithCompanion > 0 else { return 0 }
        return (totalCompanionSeconds / 60) / daysWithCompanion
    }
}

enum PetGrowthStats {
    static func monthKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    static func lastNDayKeys(_ n: Int, calendar: Calendar = .current, now: Date = Date()) -> [String] {
        guard n > 0 else { return [] }
        var keys: [String] = []
        let f = Self.dayFormatter()
        for back in 0 ..< n {
            if let d = calendar.date(byAdding: .day, value: -back, to: now) {
                keys.append(f.string(from: d))
            }
        }
        return keys
    }

    static func companionMinutes(on dayKey: String, journal: [PetCompanionDayStats]) -> Int {
        let sec = journal.first(where: { $0.dayKey == dayKey })?.companionSeconds ?? 0
        return sec / 60
    }

    static func summaryForMonth(
        yearMonthKey: String,
        journal: [PetCompanionDayStats],
        calendar: Calendar = .current
    ) -> PetGrowthMonthSummary {
        let parts = yearMonthKey.split(separator: "-")
        let y = parts.count >= 2 ? Int(parts[0]) ?? 0 : 0
        let m = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0
        var daysWith = 0
        var totalC = 0
        var totalF = 0
        var totalP = 0
        var totalE = 0
        for row in journal where row.dayKey.hasPrefix(yearMonthKey) {
            if row.companionSeconds > 0 { daysWith += 1 }
            totalC += row.companionSeconds
            totalF += row.feedCount
            totalP += row.petCount
            totalE += row.decayEventCount
        }
        let streak = bestCompanionStreakInMonth(year: y, month: m, journal: journal, calendar: calendar)
        return PetGrowthMonthSummary(
            yearMonthKey: yearMonthKey,
            daysWithCompanion: daysWith,
            totalCompanionSeconds: totalC,
            totalFeedCount: totalF,
            totalPetCount: totalP,
            totalDecayEvents: totalE,
            bestStreakDaysWithCompanion: streak
        )
    }

    private static func bestCompanionStreakInMonth(
        year: Int,
        month: Int,
        journal: [PetCompanionDayStats],
        calendar: Calendar
    ) -> Int {
        guard year > 0, month > 1 else { return 0 }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let start = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: start)
        else { return 0 }
        let f = dayFormatter()
        var best = 0
        var cur = 0
        for day in range {
            comps.day = day
            guard let d = calendar.date(from: comps) else { continue }
            let key = f.string(from: d)
            let sec = journal.first(where: { $0.dayKey == key })?.companionSeconds ?? 0
            if sec > 0 {
                cur += 1
                best = max(best, cur)
            } else {
                cur = 0
            }
        }
        return best
    }

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
