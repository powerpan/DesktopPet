//
// PetCareModel.swift
// 轻量饲养：心情/能量、每日重置、喂食与戳戳冷却、陪伴时长累计。
//

import Combine
import Foundation
import SwiftUI

private enum PetCareKeys {
    static let state = "DesktopPet.care.state"
    static let feedCooldownSeconds = "DesktopPet.care.feedCooldownSeconds"
    static let petCooldownSeconds = "DesktopPet.care.petCooldownSeconds"
}

@MainActor
final class PetCareModel: ObservableObject {
    @Published private(set) var state: PetCareState
    /// 喂食冷却（秒），默认 4 小时；可在「智能体设置 → 成长」调整。
    @Published var feedCooldownSeconds: Int
    /// 戳戳冷却（秒），默认 30 秒。
    @Published var petCooldownSeconds: Int

    private let defaults = UserDefaults.standard
    private var companionTick: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var feedCooldown: TimeInterval { TimeInterval(feedCooldownSeconds) }
    private var petCooldown: TimeInterval { TimeInterval(petCooldownSeconds) }

    private static func clampFeedCooldown(_ v: Int) -> Int { min(86_400, max(300, v)) }
    private static func clampPetCooldown(_ v: Int) -> Int { min(600, max(5, v)) }

    init() {
        if let data = defaults.data(forKey: PetCareKeys.state),
           let decoded = try? JSONDecoder().decode(PetCareState.self, from: data) {
            state = decoded
        } else {
            state = PetCareState.neutral
        }
        let feedDef = 4 * 60 * 60
        let petDef = 30
        feedCooldownSeconds = Self.clampFeedCooldown(defaults.object(forKey: PetCareKeys.feedCooldownSeconds) as? Int ?? feedDef)
        petCooldownSeconds = Self.clampPetCooldown(defaults.object(forKey: PetCareKeys.petCooldownSeconds) as? Int ?? petDef)
        ensureDayResetIfNeeded()

        $feedCooldownSeconds
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] v in
                guard let self else { return }
                let c = Self.clampFeedCooldown(v)
                if c != v {
                    self.feedCooldownSeconds = c
                } else {
                    self.defaults.set(c, forKey: PetCareKeys.feedCooldownSeconds)
                }
            }
            .store(in: &cancellables)
        $petCooldownSeconds
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] v in
                guard let self else { return }
                let c = Self.clampPetCooldown(v)
                if c != v {
                    self.petCooldownSeconds = c
                } else {
                    self.defaults.set(c, forKey: PetCareKeys.petCooldownSeconds)
                }
            }
            .store(in: &cancellables)
    }

    func startCompanionTicking(isPetVisible: @escaping () -> Bool) {
        companionTick?.invalidate()
        companionTick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.ensureDayResetIfNeeded()
                guard isPetVisible() else { return }
                var s = self.state
                s.todayCompanionSeconds += 1
                self.state = s
                self.persist()
            }
        }
        if let companionTick {
            RunLoop.main.add(companionTick, forMode: .common)
        }
    }

    func stopCompanionTicking() {
        companionTick?.invalidate()
        companionTick = nil
    }

    private func dayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func ensureDayResetIfNeeded() {
        let today = dayKey()
        if state.lastResetDayKey != today {
            var s = state
            s.lastResetDayKey = today
            s.todayCompanionSeconds = 0
            s.mood = min(1, s.mood + 0.05)
            s.energy = min(1, s.energy + 0.05)
            state = s
            persist()
        }
    }

    func feedIfAllowed() -> Bool {
        if let last = state.lastFeedAt, Date().timeIntervalSince(last) < feedCooldown {
            return false
        }
        var s = state
        s.lastFeedAt = Date()
        s.mood = min(1, s.mood + 0.12)
        s.energy = min(1, s.energy + 0.15)
        state = s
        persist()
        return true
    }

    func petIfAllowed() -> Bool {
        if let last = state.lastPetAt, Date().timeIntervalSince(last) < petCooldown {
            return false
        }
        var s = state
        s.lastPetAt = Date()
        s.mood = min(1, s.mood + 0.06)
        state = s
        persist()
        return true
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: PetCareKeys.state)
        }
    }
}

/// 饲养动作成功后，拼进「饲养互动」触发器 user 模板 `{careContext}` 的说明段。
enum PetCareNarrativeContext {
    static func summaryLine(isFeed: Bool, before: PetCareState, after: PetCareState) -> String {
        let actionName = isFeed ? "喂食" : "戳一戳（抚摸）"
        func pct(_ v: Double) -> String {
            let c = min(1, max(0, v))
            return String(format: "%.0f%%", c * 100)
        }
        func deltaLine(_ d: Double) -> String {
            if abs(d) < 0.0005 { return "基本持平" }
            let pts = abs(d) * 100
            return d > 0 ? "约升 \(String(format: "%.0f", pts)) 个百分点" : "约降 \(String(format: "%.0f", pts)) 个百分点"
        }
        let moodDelta = after.mood - before.mood
        let energyDelta = after.energy - before.energy
        let companionMin = after.todayCompanionSeconds / 60
        return """
        「\(actionName)」已成功生效（非冷却拒绝）。
        心情：操作前约 \(pct(before.mood)) → 操作后约 \(pct(after.mood))（\(deltaLine(moodDelta))）。
        能量：操作前约 \(pct(before.energy)) → 操作后约 \(pct(after.energy))（\(deltaLine(energyDelta))）。
        今日在宠物窗口可见时累计陪伴约 \(companionMin) 分钟（为当前快照，供你写反应时参考，勿像报表一样对用户复读数字）。
        """
    }
}
