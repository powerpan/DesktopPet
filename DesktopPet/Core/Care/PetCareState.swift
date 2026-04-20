//
// PetCareState.swift
// 饲养状态快照（Codable，持久化）。
//

import Foundation

struct PetCareState: Codable, Equatable {
    /// 0...1 心情
    var mood: Double
    /// 0...1 能量
    var energy: Double
    /// 上次喂食时间戳（可选）
    var lastFeedAt: Date?
    /// 上次「戳一戳」互动
    var lastPetAt: Date?
    /// 用于每日重置的日历日（yyyy-MM-dd）
    var lastResetDayKey: String
    /// 今日累计陪伴秒（宠物窗口可见时由模型累加）
    var todayCompanionSeconds: Int

    // MARK: - 成长 / 衰减（旧存档缺省）

    /// 上次完成「按小时」衰减计算的时间锚点；用于跨小时补算
    var lastDecayAt: Date?
    /// 按日聚合：陪伴秒、喂食次数、戳戳次数、成长事件次数
    var companionDailyJournal: [PetCompanionDayStats]
    /// 最近成长衰减事件（本地 + AI）
    var recentDecayEvents: [PetDecayEventRecord]
    /// 上次成功应用 AI 成长事件的时间（用于节流）
    var lastAIGrowthEventAt: Date?
    /// 上次触发「数值与成长旁白」自动化的时间（与 `PetGrowthConfig.statNarrativeCooldownMinutes` 配合）
    var lastPetStatNarrativeAt: Date?

    enum CodingKeys: String, CodingKey {
        case mood
        case energy
        case lastFeedAt
        case lastPetAt
        case lastResetDayKey
        case todayCompanionSeconds
        case lastDecayAt
        case companionDailyJournal
        case recentDecayEvents
        case lastAIGrowthEventAt
        case lastPetStatNarrativeAt
    }

    init(
        mood: Double,
        energy: Double,
        lastFeedAt: Date?,
        lastPetAt: Date?,
        lastResetDayKey: String,
        todayCompanionSeconds: Int,
        lastDecayAt: Date?,
        companionDailyJournal: [PetCompanionDayStats],
        recentDecayEvents: [PetDecayEventRecord],
        lastAIGrowthEventAt: Date?,
        lastPetStatNarrativeAt: Date? = nil
    ) {
        self.mood = mood
        self.energy = energy
        self.lastFeedAt = lastFeedAt
        self.lastPetAt = lastPetAt
        self.lastResetDayKey = lastResetDayKey
        self.todayCompanionSeconds = todayCompanionSeconds
        self.lastDecayAt = lastDecayAt
        self.companionDailyJournal = companionDailyJournal
        self.recentDecayEvents = recentDecayEvents
        self.lastAIGrowthEventAt = lastAIGrowthEventAt
        self.lastPetStatNarrativeAt = lastPetStatNarrativeAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mood = try c.decode(Double.self, forKey: .mood)
        energy = try c.decode(Double.self, forKey: .energy)
        lastFeedAt = try c.decodeIfPresent(Date.self, forKey: .lastFeedAt)
        lastPetAt = try c.decodeIfPresent(Date.self, forKey: .lastPetAt)
        lastResetDayKey = try c.decodeIfPresent(String.self, forKey: .lastResetDayKey) ?? ""
        todayCompanionSeconds = try c.decodeIfPresent(Int.self, forKey: .todayCompanionSeconds) ?? 0
        lastDecayAt = try c.decodeIfPresent(Date.self, forKey: .lastDecayAt)
        companionDailyJournal = try c.decodeIfPresent([PetCompanionDayStats].self, forKey: .companionDailyJournal) ?? []
        recentDecayEvents = try c.decodeIfPresent([PetDecayEventRecord].self, forKey: .recentDecayEvents) ?? []
        lastAIGrowthEventAt = try c.decodeIfPresent(Date.self, forKey: .lastAIGrowthEventAt)
        lastPetStatNarrativeAt = try c.decodeIfPresent(Date.self, forKey: .lastPetStatNarrativeAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mood, forKey: .mood)
        try c.encode(energy, forKey: .energy)
        try c.encodeIfPresent(lastFeedAt, forKey: .lastFeedAt)
        try c.encodeIfPresent(lastPetAt, forKey: .lastPetAt)
        try c.encode(lastResetDayKey, forKey: .lastResetDayKey)
        try c.encode(todayCompanionSeconds, forKey: .todayCompanionSeconds)
        try c.encodeIfPresent(lastDecayAt, forKey: .lastDecayAt)
        try c.encode(companionDailyJournal, forKey: .companionDailyJournal)
        try c.encode(recentDecayEvents, forKey: .recentDecayEvents)
        try c.encodeIfPresent(lastAIGrowthEventAt, forKey: .lastAIGrowthEventAt)
        try c.encodeIfPresent(lastPetStatNarrativeAt, forKey: .lastPetStatNarrativeAt)
    }

    static let neutral = PetCareState(
        mood: 0.65,
        energy: 0.7,
        lastFeedAt: nil,
        lastPetAt: nil,
        lastResetDayKey: "",
        todayCompanionSeconds: 0,
        lastDecayAt: nil,
        companionDailyJournal: [],
        recentDecayEvents: [],
        lastAIGrowthEventAt: nil,
        lastPetStatNarrativeAt: nil
    )
}
