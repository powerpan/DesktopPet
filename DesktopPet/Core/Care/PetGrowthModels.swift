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
    /// 每小时是否尝试触发「随机成长事件」的概率权重 0...100（再乘以时段系数）
    var randomEventDensityPercent: Int
    /// 是否允许调用模型生成成长事件（失败则回退本地）
    var aiGrowthEventsEnabled: Bool
    /// 两次 AI 成长事件之间最少间隔（小时）
    var aiGrowthEventsMinIntervalHours: Double

    static let `default` = PetGrowthConfig(
        energyDrainPerHour: 0.02,
        moodDrainPerHour: 0.012,
        randomEventDensityPercent: 35,
        aiGrowthEventsEnabled: false,
        aiGrowthEventsMinIntervalHours: 6
    )

    static func clamped(_ c: PetGrowthConfig) -> PetGrowthConfig {
        var o = c
        o.energyDrainPerHour = min(0.5, max(0, o.energyDrainPerHour))
        o.moodDrainPerHour = min(0.5, max(0, o.moodDrainPerHour))
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
