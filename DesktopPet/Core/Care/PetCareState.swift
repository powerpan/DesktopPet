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

    static let neutral = PetCareState(
        mood: 0.65,
        energy: 0.7,
        lastFeedAt: nil,
        lastPetAt: nil,
        lastResetDayKey: "",
        todayCompanionSeconds: 0
    )
}
